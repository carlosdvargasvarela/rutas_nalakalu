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
    qb_modified_at = parse_qb_time(so["time_modified"])

    Rails.logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Rails.logger.info "📦 ORDEN: #{order_number} | TxnID: #{qb_txn_id} | QB modified: #{qb_modified_at}"

    existing = Order.find_by(number: order_number)

    if existing.present?
      if existing.qb_txn_id.blank?
        # Orden pre-integración: vincular y procesar
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id (pre-integración)"
        return
      end

      # Orden ya importada: solo re-procesar si QB tiene cambios más nuevos
      if existing.qb_updated_at.present? && qb_modified_at.present? && existing.qb_updated_at >= qb_modified_at
        Rails.logger.info "⏭️ Saltando #{order_number}: sin cambios nuevos (local: #{existing.qb_updated_at}, QB: #{qb_modified_at})"
        return
      end

      Rails.logger.info "🔄 Re-procesando #{order_number}: cambios detectados en QB (#{qb_modified_at} > #{existing.qb_updated_at})"
    end

    due_date = so["due_date"]&.strip
    client_name = so.dig("customer_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    Rails.logger.info "📅 due_date: #{due_date.inspect}"
    Rails.logger.info "👤 client_name: #{client_name.inspect}"
    Rails.logger.info "📍 address: #{address.inspect}"
    Rails.logger.info "🧑‍💼 seller_code: #{seller_code.inspect}"

    contact_name = find_ext(so["data_ext_ret"], "Contacto de Entrega").to_s.strip
    contact_phone = find_ext(so["data_ext_ret"], "Celular de Contacto Entrega").to_s.strip

    if contact_name.blank? && contact_phone.blank?
      contact_name = so.dig("ship_address", "addr2").to_s.gsub(/^Contacto:\s*/i, "").strip
      contact_phone = so.dig("ship_address", "city").to_s.gsub(/^Telefono:\+?506\s*/i, "").strip
    end

    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")
    Rails.logger.info "📞 contact: #{full_contact.inspect}"

    lines = so["sales_order_line_ret"]
    lines = [lines] if lines.is_a?(Hash)
    lines = [] if lines.blank?

    Rails.logger.info "📝 Cantidad de líneas: #{lines.size}"

    lines.each_with_index do |line, idx|
      Rails.logger.info "  --- LÍNEA #{idx + 1} ---"

      line_id = line["txn_line_id"]
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)
      quantity = line["quantity"].to_s.tr(",", ".").to_f

      Rails.logger.info "  🪑 raw_item: #{raw_item.inspect} → product_name: #{product_name.inspect}"
      Rails.logger.info "  🔢 quantity: #{quantity.inspect}"

      chars = (1..6).map do |i|
        val = find_ext(line["data_ext_ret"], "Caracteristica#{i}")
        Rails.logger.info "    Caracteristica#{i}: #{val.inspect}"
        val
      end.select(&:present?)

      Rails.logger.info "  ✅ chars finales: #{chars.inspect}"

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
        time_preference: nil,
        qb_line_id: line_id
      }

      Rails.logger.info "  📤 row_data: #{row_data.inspect}"

      RouteExcelImportService.new(nil).send(:process_row, row_data)
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error en línea #{order_number} / #{raw_item}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
    end

    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
    end

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

  def parse_qb_time(value)
    return nil if value.blank?
    Time.zone.parse(value)
  rescue ArgumentError, TypeError
    nil
  end
end
