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

    # Contacto
    order_ext = Array.wrap(so["data_ext_ret"])
    contact_name = find_ext(order_ext, "ContactoEntrega")
    contact_phone = find_ext(order_ext, "CelularEntrega")
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    # Líneas
    lines = Array.wrap(so["sales_order_line_ret"])

    lines.each do |line|
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)

      # fallback a descripción
      line_description = line["desc"].to_s.strip
      final_base_name = line_description.present? ? line_description : product_name

      # Características
      line_ext = Array.wrap(line["data_ext_ret"])
      chars = (2..6).map { |i| find_ext(line_ext, "Caracteristica#{i}") }.select(&:present?)

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

      # ✅ FIX AQUÍ
      service = RouteExcelImportService.new(nil)
      service.send(:process_row, row_data)

      Rails.logger.info "✅ Importado #{order_number} - #{full_product} - Cantidad: #{line["quantity"]}"
    end
  end

  def find_ext(ext_array, name)
    ext_array.find { |e| e["data_ext_name"] == name }&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    # Caso 1: "008000100 (Espejo de cuerpo entero)"
    if name =~ /\((.+)\)/
      return $1.strip
    end

    # Caso 2: "008000100 Espejo..."
    parts = name.split(/\s+/, 2)
    if parts.first =~ /^\d+$/ && parts.size == 2
      return parts.last.strip
    end

    name.strip
  end
end
