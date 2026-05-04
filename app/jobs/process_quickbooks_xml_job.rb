class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(orders)
    orders = Array.wrap(orders)

    orders.each do |so|
      process_sales_order(so)
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error procesando SO #{so["ref_number"]}: #{e.message}"
    end
  end

  private

  def process_sales_order(so)
    order_number = "PED-#{so["ref_number"]}"
    due_date = so["due_date"]
    client_name = so.dig("customer_ref", "full_name")
    address = so.dig("ship_address", "addr1")
    seller_code = so.dig("sales_rep_ref", "full_name")

    # Extraer Contactos (DataExt a nivel Orden)
    order_ext = Array.wrap(so["data_ext_ret"])
    contact_name = find_ext(order_ext, "ContactoEntrega")
    contact_phone = find_ext(order_ext, "CelularEntrega")
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    # Detalle de productos
    lines = Array.wrap(so["sales_order_line_ret"])

    lines.each_with_index do |line, index|
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)

      # Características (DataExt a nivel Línea)
      line_ext = Array.wrap(line["data_ext_ret"])
      chars = (2..6).map { |i| find_ext(line_ext, "Caracteristica#{i}") }.select(&:present?)

      full_product = [product_name, chars.join("    ")].select(&:present?).join("    ")

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

      # IMPORTANTE: Llamada al servicio original de rutas
      # service = RouteExcelImportService.new(nil)
      # service.send(:process_row, row_data, index)

      Rails.logger.info "ProcessQuickbooksXmlJob: Importado #{order_number} - #{product_name}- Cantidad: #{line["quantity"]} - Cliente: #{client_name} - Vendedor: #{seller_code} - Contacto: #{full_contact} - Dirección: #{address}"
    end
  end

  def find_ext(ext_array, name)
    ext_array.find { |e| e["data_ext_name"] == name }&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    cleaned = name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
    cleaned.presence || name.strip
  end
end
