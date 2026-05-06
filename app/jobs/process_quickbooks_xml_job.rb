class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(orders_payload)
    orders = Array.wrap(orders_payload)
    orders_processed = 0
    errors = []

    orders.each do |so|
      process_sales_order(so, errors)
      orders_processed += 1
    rescue => e
      errors << "Orden desconocida: #{e.message}"
      Rails.logger.error "ProcessQuickbooksXmlJob error procesando orden: #{e.message}"
    end

    Rails.logger.info "ProcessQuickbooksXmlJob: #{orders_processed} órdenes procesadas. Errores: #{errors.size}"
    errors.each { |e| Rails.logger.warn "  - #{e}" }
  end

  private

  def process_sales_order(so, errors)
    qb_txn_id = so["txn_id"]
    order_number = "PED-#{so["ref_number"]&.strip}"
    due_date = so["due_date"]&.strip
    client_name = so.dig("customer_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1").presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    order_ext = so["data_ext_ret"]
    contact_entrega = data_ext_value(order_ext, "ContactoEntrega")
    celular_entrega = data_ext_value(order_ext, "CelularEntrega")
    full_contact = [contact_entrega, celular_entrega].select(&:present?).join(" / ")

    # ── Evitar duplicados ──
    existing = Order.find_by(number: order_number)
    if existing.present?
      if existing.qb_txn_id.blank? && qb_txn_id.present?
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id: #{qb_txn_id} (pre-integración)"
      else
        Rails.logger.info "⏭️ Saltando #{order_number}: ya existe en sistema"
      end
      return
    end

    lines = so["sales_order_line_ret"]
    lines = [lines] if lines.is_a?(Hash)
    lines = [] if lines.blank?

    lines.each do |line|
      line_id = line["txn_line_id"]
      raw_product = line.dig("item_ref", "full_name").to_s
      product_base = clean_product_name(raw_product)

      # Características 1 al 6 desde DataExt de la línea
      # Se concatenan con un TAB (\t) según requerimiento
      line_ext = line["data_ext_ret"]
      chars = (1..6).map { |i| data_ext_value(line_ext, "Caracteristica#{i}") }
        .select(&:present?)

      full_product = ([product_base] + chars).join("\t")

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
        notes: so["memo"], # Importamos el memo de QB como notas
        time_preference: nil
      }

      Rails.logger.info "ProcessQuickbooksXmlJob: Creando #{order_number} | Item: #{full_product}"

      # Llamada al servicio existente que ya sabe procesar este Hash
      RouteExcelImportService.new(nil).send(:process_row, row_data, 0)

      # ── Vincular qb_line_id al item recién creado ──
      if line_id.present?
        order = Order.find_by(number: order_number)
        item = order&.order_items&.find_by(qb_line_id: line_id)
        item ||= order&.order_items&.find_by(product: full_product, qb_line_id: nil)
        item&.update_columns(qb_line_id: line_id) if item&.qb_line_id.blank?
      end
    rescue => e
      errors << "#{order_number} / #{raw_product}: #{e.message}"
      Rails.logger.error "ProcessQuickbooksXmlJob error en línea: #{e.message}"
    end

    # ── Finalizar vinculación de la orden ──
    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)

      # Registrar evento
      order.deliveries.each do |delivery|
        DeliveryEvent.record(
          delivery: delivery,
          action: "created",
          actor: nil,
          payload: {source: "quickbooks", qb_txn_id: qb_txn_id}
        )
      end
    end
  end

  def data_ext_value(data_ext_ret, target_name)
    entries = case data_ext_ret
    when Array then data_ext_ret
    when Hash then [data_ext_ret]
    else []
    end

    entry = entries.find { |item| item["data_ext_name"] == target_name }
    val = entry&.dig("data_ext_value")&.strip

    # Limpiar valores que no aportan información
    return nil if val.blank? || val.to_s.downcase == "nan" || val == "0"
    val
  end

  def clean_product_name(name)
    # Ejemplo: "008000100 (Espejo de cuerpo entero)" -> "Espejo de cuerpo entero"
    if name =~ /\((.+)\)/
      $1.strip
    else
      # Si no hay paréntesis, quitar el SKU inicial si existe (ej. "001 Producto")
      name.split(/\s+/, 2).last.strip
    end
  end
end
