class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  # El pedido se guardó completo pero en stand-by (no operativo); solo se avisa a admins.
  class HeldInStandby < StandardError; end

  def perform(orders)
    orders = Array.wrap(orders)
    results_by_seller = Hash.new { |h, k| h[k] = [] }
    rejected = []

    orders.each do |so|
      result = process_sales_order(so)
      results_by_seller[result[:seller_code]] << result if result
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error en SO #{so["ref_number"]}: #{e.message}"
      hold_after_error(so, e) unless e.is_a?(HeldInStandby)
      rejected << {order_number: so["ref_number"].to_s.strip, reason: e.message}
    end

    send_import_notifications(results_by_seller) if results_by_seller.any?
    send_rejection_notifications(rejected) if rejected.any?
  end

  private

  def process_sales_order(so)
    qb_txn_id = so["txn_id"]
    ref_number = so["ref_number"].to_s.strip
    order_number = ref_number.start_with?("PED-") ? ref_number : "PED-#{ref_number}"
    qb_modified_at = parse_qb_time(so["time_modified"])
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    # Esta transacción ya está en el sistema, retenida o liberada con otro número: QB la reenvía
    # (traslape de 5 min, ediciones) y no debe duplicarse ni tocar nada.
    known = qb_txn_id.present? && Order.find_by(qb_txn_id: qb_txn_id)
    return if known && (known.qb_standby || known.number != order_number)

    existing = Order.find_by(number: order_number, qb_standby: false)

    if existing.present?
      if existing.qb_txn_id.blank?
        Rails.logger.info "🚫 Ignorando #{order_number}: pre-integración"
        return
      end

      # Mismo número, otra transacción de QB: jamás se pisa el pedido existente.
      if qb_txn_id.present? && existing.qb_txn_id != qb_txn_id
        hold_in_standby(so, order_number, ["#{order_number} ya existe (cliente #{existing.client&.name}) con otra transacción de QuickBooks"])
      end

      if existing.qb_updated_at.present? && qb_modified_at.present? && existing.qb_updated_at >= qb_modified_at
        return
      end
    end

    due_date = so["due_date"]&.strip
    lines = merge_duplicate_product_lines(Array.wrap(so["sales_order_line_ret"]).compact)

    if existing.blank?
      problems = incomplete_data_problems(so, due_date, lines)
      hold_in_standby(so, order_number, problems) if problems.any?
    end

    if existing.present?
      lines_changed = update_order_lines(existing, lines, due_date)
      event_action = lines_changed ? "updated" : nil
    else
      Order.transaction { create_order_from_so(so, order_number, due_date, lines) }
      event_action = "created"
    end

    order = existing || Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
      if event_action.present?
        order.deliveries.each do |delivery|
          DeliveryEvent.record(delivery: delivery, action: event_action, payload: {source: "quickbooks"})
        end
      end
    end

    return unless event_action.present?

    {
      seller_code: seller_code,
      order_number: order_number,
      client_name: so.dig("customer_ref", "full_name")&.strip,
      delivery_date: due_date,
      action: event_action,
      items: lines.map { |l| {product: build_product_name(l), quantity: l["quantity"].to_s.tr(",", ".").to_f} },
      notes: so["memo"]&.strip.presence
    }
  end

  def send_import_notifications(results_by_seller)
    results_by_seller.each do |seller_code, orders_data|
      seller = Seller.find_by(seller_code: seller_code)
      next unless seller&.user&.send_notifications?
      QuickbooksImportMailer.with(seller: seller, orders_data: orders_data)
        .seller_orders_loaded.deliver_later
    end

    User.where(role: :admin).find_each do |admin|
      next unless admin.send_notifications?
      QuickbooksImportMailer.with(admin: admin, results_by_seller: results_by_seller)
        .admin_orders_loaded.deliver_later
    end
  end

  def send_rejection_notifications(rejected)
    User.where(role: :admin).find_each do |admin|
      next unless admin.send_notifications?
      QuickbooksImportMailer.with(admin: admin, rejected: rejected)
        .admin_orders_rejected.deliver_later
    end
  end

  PLACEHOLDER_ADDRESS = "Vendedor no agregó dirección"
  PLACEHOLDER_CLIENT = "SIN CLIENTE (QuickBooks)"
  PLACEHOLDER_SELLER_CODE = "SIN-ASIGNAR"

  def incomplete_data_problems(so, due_date, lines)
    [
      ("sin nombre de cliente" if so.dig("customer_ref", "full_name").blank?),
      ("sin dirección de entrega" if so.dig("ship_address", "addr1").blank?),
      ("sin productos" if lines.empty?),
      ("sin fecha de entrega" if due_date.blank?)
    ].compact
  end

  # Guarda lo que QB mandó como pedido real pero NO operativo: qb_standby=true y
  # entrega en "Pendiente de revisión" (fuera de rutas/listados) hasta que un admin lo revise y libere.
  # Tolera datos faltantes; solo exige vendedor (orders.seller_id es NOT NULL).
  def hold_in_standby(so, order_number, problems)
    reason = problems.join("; ").truncate(250)
    lines = merge_duplicate_product_lines(Array.wrap(so["sales_order_line_ret"]).compact)
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip
    seller = Seller.find_by(seller_code: seller_code)
    if seller.nil?
      # orders.seller_id es NOT NULL: se asigna un vendedor "sin asignar" hasta que un admin elija el real.
      seller = Seller.find_by(seller_code: PLACEHOLDER_SELLER_CODE) ||
        Seller.create!(user: User.admin.first!, name: "Sin asignar (QuickBooks)", seller_code: PLACEHOLDER_SELLER_CODE)
      problems += ["vendedor #{seller_code.inspect} no existe"] unless problems.any? { |p| p.start_with?("Vendedor") }
      reason = problems.join("; ").truncate(250)
    end
    client = Client.find_or_create_by!(name: so.dig("customer_ref", "full_name")&.strip.presence || PLACEHOLDER_CLIENT)

    Order.transaction do
      order = Order.create!(number: order_number, client: client, seller: seller, status: :in_production,
        qb_standby: true, qb_standby_reason: reason, qb_txn_id: so["txn_id"],
        qb_updated_at: parse_qb_time(so["time_modified"]) || Time.current)
      primary, extra = contacts_from_so(so)
      add_contact(order, primary)
      add_contact(order, extra)
      address = client.delivery_addresses.find_or_create_by!(address: so.dig("ship_address", "addr1")&.strip.presence || PLACEHOLDER_ADDRESS)
      delivery = order.deliveries.create!(delivery_address: address, status: :pending_review,
        contact_name: primary[0].presence, contact_phone: primary[1].presence,
        delivery_date: (Date.parse(so["due_date"].to_s) rescue Date.current), delivery_notes: so["memo"]&.strip.presence)
      lines.each do |line|
        qty = parse_quantity(line["quantity"]).to_i.clamp(1, 100_000)
        item = order.order_items.create!(product: build_product_name(line).presence || "(sin producto)", quantity: qty,
          qb_line_id: line["txn_line_id"], status: :in_production)
        delivery.delivery_items.create!(order_item: item, quantity_delivered: qty, status: :pending)
      end
    end
    raise HeldInStandby, "#{order_number}: #{reason}; quedó en stand-by, no se sobrescribió ni se usa"
  end

  # Error inesperado: se intenta igual dejar el pedido en stand-by; si tampoco se puede
  # armar (p. ej. vendedor inexistente), se conserva el contenido crudo en QbStandbyOrder.
  def hold_after_error(so, error)
    hold_in_standby(so, so["ref_number"].to_s.strip.then { |r| r.start_with?("PED-") ? r : "PED-#{r}" }, [error.message])
  rescue HeldInStandby
    nil
  rescue => e
    Rails.logger.error "ProcessQuickbooksXmlJob: no se pudo dejar en stand-by: #{e.message}"
    QbStandbyOrder.hold(so, so["ref_number"].to_s.strip, error.message) if so["txn_id"].present?
  end

  def create_order_from_so(so, order_number, due_date, lines)
    client_name = so.dig("customer_ref", "full_name")&.strip
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "Vendedor no agregó dirección"

    primary, extra = contacts_from_so(so)
    full_contact = primary.select(&:present?).join(" / ")

    lines.each do |line|
      full_product = build_product_name(line)
      row_data = {
        order_number: order_number,
        product: full_product,
        quantity: line["quantity"].to_s.tr(",", ".").to_f,
        qb_line_id: line["txn_line_id"],
        delivery_date: due_date,
        client_name: client_name,
        seller_code: seller_code,
        place: address,
        contact: full_contact,
        notes: so["memo"]
      }
      RouteExcelImportService.new.process_row(row_data)
    end

    add_contact(Order.find_by(number: order_number, qb_standby: false), extra)
  end

  # [[nombre, teléfono] principal, [nombre, teléfono] extra o nil]. El principal sale de los
  # campos "Contacto de Entrega" de QB; si el bloque de dirección trae OTRO contacto
  # ("Contacto: ..." / "Telefono:+506..."), va como contacto adicional del pedido.
  def contacts_from_so(so)
    ext = [find_ext(so["data_ext_ret"], "Contacto de Entrega").to_s.strip,
      find_ext(so["data_ext_ret"], "Celular de Contacto Entrega").to_s.strip]
    ship = so["ship_address"] || {}
    addr = [ship["addr2"].to_s.gsub(/^Contacto:\s*/i, "").strip,
      (ship["city"].presence || ship["addr3"]).to_s.gsub(/^Telefono:\s*\+?506\s*/i, "").strip]
    return [addr, nil] if ext.none?(&:present?)
    return [ext, nil] if addr.none?(&:present?)

    digits = ->(c) { c[1].to_s.gsub(/\D/, "").delete_prefix("506") }
    same = digits.(ext).present? ? digits.(ext) == digits.(addr) : (digits.(addr).blank? && ext[0].casecmp?(addr[0]))
    [ext, (addr unless same)]
  end

  def add_contact(order, contact)
    return if order.nil? || contact.nil?
    name, phone = contact
    return if phone.present? && order.order_contacts.any? { |c| c.phone.to_s.gsub(/\D/, "") == phone.gsub(/\D/, "") }
    order.order_contacts.create!(name: name.presence || "Contacto (dirección)", phone: phone.presence, is_primary: order.order_contacts.none?)
  end

  def update_order_lines(order, lines, due_date)
    changed = false

    lines.each do |line|
      qb_line_id = line["txn_line_id"]
      new_qty = line["quantity"].to_s.tr(",", ".").to_f.to_i

      order_item = order.order_items.find_by(qb_line_id: qb_line_id)

      if order_item
        if order_item.quantity != new_qty
          order_item.update!(quantity: new_qty)
          changed = true
        end
      else
        full_product = build_product_name(line)
        order_item = order.order_items.find_or_initialize_by(product: full_product)
        order_item.assign_attributes(quantity: new_qty, qb_line_id: qb_line_id, status: :in_production)
        order_item.save!
        changed = true

        delivery = order.deliveries.find_by(delivery_date: due_date)
        if delivery
          di = delivery.delivery_items.find_or_initialize_by(order_item: order_item)
          di.assign_attributes(quantity_delivered: new_qty, status: :pending)
          di.save!
        end
      end
    end

    changed
  end

  # ponytail: OrderItem exige un producto único por pedido, así que dos líneas de QB
  # con el mismo producto deben sumarse en una sola línea antes de tocar la BD
  # (si no, la segunda sobrescribe la cantidad de la primera en vez de sumarla).
  def merge_duplicate_product_lines(lines)
    merged = {}
    lines.each do |line|
      key = build_product_name(line)
      qty = parse_quantity(line["quantity"])
      if merged[key]
        merged[key] = merged[key].merge("quantity" => (merged[key]["quantity"].to_s.tr(",", ".").to_f + qty).to_s)
      else
        merged[key] = line.merge("quantity" => qty.to_s)
      end
    end
    merged.values
  end

  # ponytail: QB a veces manda la cantidad vacía; en vez de rebotar el pedido
  # completo (falla la validación quantity > 0 de OrderItem), se carga con 1.
  def parse_quantity(raw)
    qty = raw.to_s.tr(",", ".").to_f
    qty.positive? ? qty : 1.0
  end

  def build_product_name(line)
    product_base = line["desc"].to_s.strip.presence || clean_product_name(line.dig("item_ref", "full_name").to_s)
    chars = (1..6).map { |i| find_ext(line["data_ext_ret"], "Caracteristica#{i}") }.select(&:present?)
    chars.any? ? [product_base, chars.join("    ")].join("    ") : product_base
  end

  def find_ext(data_ext_ret, target_name)
    entries = Array.wrap(data_ext_ret).compact
    entry = entries.find { |item| item["data_ext_name"] == target_name }
    entry&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
  end

  def parse_qb_time(value)
    return nil if value.blank?
    begin
      Time.zone.parse(value)
    rescue
      nil
    end
  end
end
