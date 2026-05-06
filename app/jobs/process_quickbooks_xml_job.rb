class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(orders)
    orders = Array.wrap(orders)
    Rails.logger.info "=== ProcessQuickbooksXmlJob: #{orders.size} órdenes recibidas ==="

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

    Rails.logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Rails.logger.info "📦 ORDEN: #{order_number} | TxnID: #{qb_txn_id}"
    Rails.logger.info "📋 SO completo: #{so.inspect}"
    Rails.logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    existing = Order.find_by(number: order_number)

    if existing.present? && existing.qb_txn_id.blank?
      if qb_txn_id.present?
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id: #{qb_txn_id} (pre-integración)"
      else
        Rails.logger.info "⏭️ Saltando #{order_number}: pre-integración sin qb_txn_id"
      end
      return
    end

    if existing.present? && existing.qb_txn_id.present?
      Rails.logger.info "⏭️ Saltando #{order_number}: ya fue importada desde QuickBooks (qb_txn_id: #{existing.qb_txn_id})"
      return
    end

    due_date = so["due_date"]&.strip
    client_name = so.dig("customer_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    Rails.logger.info "📅 due_date: #{due_date.inspect}"
    Rails.logger.info "👤 client_name: #{client_name.inspect}"
    Rails.logger.info "📍 address: #{address.inspect}"
    Rails.logger.info "🧑‍💼 seller_code: #{seller_code.inspect}"

    # Contacto: primero intentamos ship_address addr2/city, luego data_ext_ret como fallback
    contact_name = so.dig("ship_address", "addr2").to_s.gsub(/^Contacto:\s*/i, "").strip
    contact_phone = so.dig("ship_address", "city").to_s.gsub(/^Telefono:\+?/i, "").strip
    if contact_name.blank? && contact_phone.blank?
      contact_name = find_ext(so["data_ext_ret"], "ContactoEntrega").to_s
      contact_phone = find_ext(so["data_ext_ret"], "CelularEntrega").to_s
    end
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")
    Rails.logger.info "📞 contact: #{full_contact.inspect}"

    lines = so["sales_order_line_ret"]
    lines = [lines] if lines.is_a?(Hash)
    lines = [] if lines.blank?

    Rails.logger.info "📝 Cantidad de líneas: #{lines.size}"

    lines.each_with_index do |line, idx|
      Rails.logger.info "  --- LÍNEA #{idx + 1} ---"
      Rails.logger.info "  🔍 line completa: #{line.inspect}"

      line_id = line["txn_line_id"]
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)
      quantity = line["quantity"].to_s.tr(",", ".").to_f

      Rails.logger.info "  🪑 raw_item: #{raw_item.inspect} → product_name: #{product_name.inspect}"
      Rails.logger.info "  🔢 quantity: #{quantity.inspect}"
      Rails.logger.info "  📎 data_ext_ret (LÍNEA): #{line["data_ext_ret"].inspect}"

      chars = (1..6).map do |i|
        val = find_ext(line["data_ext_ret"], "Caracteristica#{i}")
        Rails.logger.info "    Caracteristica#{i}: #{val.inspect}"
        val
      end.select(&:present?)

      Rails.logger.info "  ✅ chars finales: #{chars.inspect}"

      # Si llegaron características custom (con OwnerID 0), las usamos.
      # Si no, usamos el desc como fallback (QB ya lo trae con nombre completo).
      full_product = if chars.any?
        [product_name, chars.join("    ")].join("    ")
      else
        line["desc"].to_s.strip.presence || product_name
      end
      Rails.logger.info "  🏷️ full_product: #{full_product.inspect}"

      row_data = {
        delivery_date: due_date,
        order_number: order_number,
        client_name: client_name,
        product: full_product,
        quantity: quantity,
        place: address,
        contact: full_contact,
        seller_code: seller_code,
        team: nil,
        notes: so["memo"],
        time_preference: nil
      }

      Rails.logger.info "  📤 row_data: #{row_data.inspect}"

      RouteExcelImportService.new(nil).send(:process_row, row_data)

      if line_id.present?
        order = Order.find_by(number: order_number)
        item = order&.order_items&.find_by(qb_line_id: line_id)
        item ||= order&.order_items&.find_by(product: full_product, qb_line_id: nil)
        item&.update_columns(qb_line_id: line_id) if item&.qb_line_id.blank?
      end
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error en línea #{order_number} / #{raw_item}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
    end

    order = Order.find_by(number: order_number)
    order&.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current) if qb_txn_id.present?

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

  def find_ext(data_ext_ret, target_name)
    entries = case data_ext_ret
    when Array then data_ext_ret
    when Hash then [data_ext_ret]
    else []
    end

    entry = entries.find { |item| item["data_ext_name"] == target_name }
    entry&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    cleaned = name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
    cleaned.presence || name.strip
  end
end
