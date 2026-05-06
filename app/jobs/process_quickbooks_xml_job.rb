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
        # Orden pre-integración: vinculamos y permitimos que procese para actualizar datos
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id (pre-integración)"
      elsif existing.qb_updated_at.present? && qb_modified_at.present? && existing.qb_updated_at >= qb_modified_at
        # Si ya la tenemos actualizada a esta fecha o más nueva, saltamos
        Rails.logger.info "⏭️ Saltando #{order_number}: sin cambios nuevos (local: #{existing.qb_updated_at}, QB: #{qb_modified_at})"
        return
      end
      Rails.logger.info "🔄 Procesando #{order_number}: cambios detectados o nueva vinculación"
    end

    due_date = so["due_date"]&.strip
    client_name = so.dig("customer_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    # Contacto de la orden (DataExt)
    contact_name = find_ext(so["data_ext_ret"], "Contacto de Entrega").to_s.strip
    contact_phone = find_ext(so["data_ext_ret"], "Celular de Contacto Entrega").to_s.strip

    # Fallback a ship_address si los DataExt están vacíos
    if contact_name.blank? && contact_phone.blank?
      contact_name = so.dig("ship_address", "addr2").to_s.gsub(/^Contacto:\s*/i, "").strip
      contact_phone = so.dig("ship_address", "city").to_s.gsub(/^Telefono:\+?506\s*/i, "").strip
    end

    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    lines = so["sales_order_line_ret"]
    lines = [lines] if lines.is_a?(Hash)
    lines = [] if lines.blank?

    lines.each_with_index do |line, idx|
      line_id = line["txn_line_id"]

      # SEGÚN TU ESTRUCTURA: 'desc' es el nombre del producto, 'item_ref > full_name' es el código
      product_base_name = line["desc"].to_s.strip
      product_code = line.dig("item_ref", "full_name").to_s.strip

      # Si por alguna razón desc está vacío, usamos el código limpio
      product_base_name = clean_product_name(product_code) if product_base_name.blank?

      quantity = line["quantity"].to_s.tr(",", ".").to_f

      # Características de la línea
      chars = (1..6).map do |i|
        find_ext(line["data_ext_ret"], "Caracteristica#{i}")
      end.select(&:present?)

      # Concatenamos nombre base + características con los 4 espacios
      full_product = if chars.any?
        [product_base_name, chars.join("    ")].join("    ")
      else
        product_base_name
      end

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

      Rails.logger.info "  📤 Row Data: #{row_data[:product]} | Cant: #{row_data[:quantity]}"
      RouteExcelImportService.new(nil).send(:process_row, row_data)
    rescue => e
      Rails.logger.error "Error en línea #{idx} de SO #{order_number}: #{e.message}"
    end

    # Actualizar marca de tiempo al finalizar para evitar re-procesar lo mismo
    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: qb_modified_at || Time.current)
    end

    # Registrar evento de creación/actualización
    order&.deliveries&.each do |delivery|
      DeliveryEvent.record(
        delivery: delivery,
        action: "created",
        actor: nil,
        payload: {source: "quickbooks", qb_txn_id: qb_txn_id}
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
    # Limpia códigos tipo "001000(Mesa)" si hiciera falta
    name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
  end

  def parse_qb_time(value)
    return nil if value.blank?
    Time.zone.parse(value)
  rescue ArgumentError, TypeError
    nil
  end
end
