class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(orders)
    orders = Array.wrap(orders)

    orders.each do |so|
      process_sales_order(so)
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error procesando SO #{so["ref_number"]}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    end
  end

  private

  def process_sales_order(so)
    qb_txn_id = so["txn_id"]
    ref_number = so["ref_number"].to_s.strip
    order_number = ref_number.start_with?("PED-") ? ref_number : "PED-#{ref_number}"

    existing = Order.find_by(number: order_number)

    # ── Órdenes pre-integración: solo vincular qb_txn_id, no tocar nada más ──
    if existing.present? && existing.qb_txn_id.blank?
      if qb_txn_id.present?
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id: #{qb_txn_id} (pre-integración, sin modificar items)"
      else
        Rails.logger.info "⏭️ Saltando #{order_number}: pre-integración sin qb_txn_id"
      end
      return
    end

    # ── Orden ya importada por QB: si ya tiene qb_txn_id, no volver a procesar ──
    if existing.present? && existing.qb_txn_id.present?
      Rails.logger.info "⏭️ Saltando #{order_number}: ya fue importada desde QuickBooks (qb_txn_id: #{existing.qb_txn_id})"
      return
    end

    # ── Orden nueva: procesamiento completo ──
    due_date = so["due_date"]
    client_name = so.dig("customer_ref", "full_name")
    address = so.dig("ship_address", "addr1").presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")

    order_ext = Array.wrap(so["data_ext_ret"])
    contact_name = find_ext(order_ext, "ContactoEntrega")
    contact_phone = find_ext(order_ext, "CelularEntrega")
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    lines = Array.wrap(so["sales_order_line_ret"])

    lines.each do |line|
      line_id = line["txn_line_id"]
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)

      line_description = line["desc"].to_s.strip
      final_base_name = line_description.present? ? line_description : product_name

      # Características 2 a 6 (la 1 se omite según requerimiento)
      line_ext = Array.wrap(line["data_ext_ret"])
      chars = (1..6).map { |i| find_ext(line_ext, "Caracteristica#{i}") }.select(&:present?)

      full_product = [final_base_name, chars.join("    ")].select(&:present?).join("    ")

      row_data = {
        delivery_date: due_date,
        order_number: order_number,
        client_name: client_name,
        product: full_product,
        quantity: line["quantity"].to_f,
        place: address,
        contact: full_contact,
        seller_code: seller_code,
        team: nil,
        notes: so["memo"],
        time_preference: nil
      }

      RouteExcelImportService.new(nil).send(:process_row, row_data)

      # ── Vincular qb_line_id usando el ID de QB como fuente de verdad ──
      if line_id.present?
        order = Order.find_by(number: order_number)

        # Primero buscar por qb_line_id (ya vinculado antes)
        item = order&.order_items&.find_by(qb_line_id: line_id)

        # Si no, buscar por producto sin qb_line_id asignado aún
        item ||= order&.order_items&.find_by(product: full_product, qb_line_id: nil)

        item&.update_columns(qb_line_id: line_id) if item&.qb_line_id.blank?
      end

      Rails.logger.info "✅ ProcessQuickbooksXmlJob: #{order_number} | #{full_product} | Cant: #{line["quantity"]} | Cliente: #{client_name} | Vendedor: #{seller_code}"
    end

    # ── Registrar qb_txn_id en la orden una vez procesada ──
    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
    end

    # ── Registrar evento de creación en DeliveryEvent ──
    order&.deliveries&.each do |delivery|
      DeliveryEvent.record(
        delivery: delivery,
        action: "created",
        actor: nil,
        payload: {
          source: "quickbooks",
          order_number: order_number,
          qb_txn_id: qb_txn_id
        }
      )
    end
  end

  def find_ext(ext_array, name)
    ext_array.find { |e| e["data_ext_name"] == name }&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    # "008000100 (Espejo de cuerpo entero)" → "Espejo de cuerpo entero"
    return $1.strip if name =~ /\((.+)\)/

    # "008000100 Espejo de cuerpo entero" → "Espejo de cuerpo entero"
    parts = name.split(/\s+/, 2)
    return parts.last.strip if parts.first =~ /^\d+$/ && parts.size == 2

    name.strip
  end
end
