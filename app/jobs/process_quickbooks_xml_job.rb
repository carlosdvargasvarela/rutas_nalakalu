class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(orders)
    orders = Array.wrap(orders)
    orders.each do |so|
      process_sales_order(so)
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error en SO #{so["ref_number"]}: #{e.message}"
    end
  end

  private

  def process_sales_order(so)
    qb_txn_id = so["txn_id"]
    ref_number = so["ref_number"].to_s.strip
    order_number = ref_number.start_with?("PED-") ? ref_number : "PED-#{ref_number}"
    qb_modified_at = parse_qb_time(so["time_modified"])

    existing = Order.find_by(number: order_number)

    if existing.present?
      if existing.qb_txn_id.blank?
        Rails.logger.info "🚫 Ignorando #{order_number}: pre-integración"
        return
      end

      if existing.qb_updated_at.present? && qb_modified_at.present? && existing.qb_updated_at >= qb_modified_at
        return
      end
    end

    due_date = so["due_date"]&.strip
    lines = Array.wrap(so["sales_order_line_ret"]).compact

    if existing.present?
      update_order_lines(existing, lines, due_date)
      event_action = "updated"
    else
      create_order_from_so(so, order_number, due_date, lines)
      event_action = "created"
    end

    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
      order.deliveries.each do |delivery|
        DeliveryEvent.record(delivery: delivery, action: event_action, payload: {source: "quickbooks"})
      end
    end
  end

  def create_order_from_so(so, order_number, due_date, lines)
    client_name = so.dig("customer_ref", "full_name")&.strip
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "Vendedor no agregó dirección"

    c_name = find_ext(so["data_ext_ret"], "Contacto de Entrega").to_s.strip
    c_phone = find_ext(so["data_ext_ret"], "Celular de Contacto Entrega").to_s.strip
    if c_name.blank? && c_phone.blank?
      c_name = so.dig("ship_address", "addr2").to_s.gsub(/^Contacto:\s*/i, "").strip
      c_phone = so.dig("ship_address", "city").to_s.gsub(/^Telefono:\+?506\s*/i, "").strip
    end
    full_contact = [c_name, c_phone].select(&:present?).join(" / ")

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
      RouteExcelImportService.new(nil).send(:process_row, row_data)
    end
  end

  def update_order_lines(order, lines, due_date)
    lines.each do |line|
      qb_line_id = line["txn_line_id"]
      new_qty = line["quantity"].to_s.tr(",", ".").to_f.to_i

      order_item = order.order_items.find_by(qb_line_id: qb_line_id)

      if order_item
        order_item.update!(quantity: new_qty) if order_item.quantity != new_qty
      else
        full_product = build_product_name(line)
        order_item = order.order_items.find_or_initialize_by(product: full_product)
        order_item.assign_attributes(quantity: new_qty, qb_line_id: qb_line_id, status: :in_production)
        order_item.save!

        delivery = order.deliveries.find_by(delivery_date: due_date)
        if delivery
          di = delivery.delivery_items.find_or_initialize_by(order_item: order_item)
          di.assign_attributes(quantity_delivered: new_qty, status: :pending)
          di.save!
        end
      end
    end
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
