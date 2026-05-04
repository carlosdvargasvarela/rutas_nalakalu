# app/jobs/process_quickbooks_xml_job.rb
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
    order_number = "PED-#{so["ref_number"]}"
    due_date = so["due_date"]
    client_name = so.dig("customer_ref", "full_name")
    address = so.dig("ship_address", "addr1")
    seller_code = so.dig("sales_rep_ref", "full_name")

    # Contacto a nivel de orden
    order_ext = Array.wrap(so["data_ext_ret"])
    contact_name = find_ext(order_ext, "ContactoEntrega")
    contact_phone = find_ext(order_ext, "CelularEntrega")
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    # Vincular qb_txn_id si la orden ya existe pero no tiene el ID de QB
    if qb_txn_id.present?
      existing = Order.find_by(number: order_number)
      if existing && existing.qb_txn_id.blank?
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
      end
    end

    lines = Array.wrap(so["sales_order_line_ret"])

    lines.each do |line|
      line_id = line["txn_line_id"]
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)

      # Fallback a descripción de línea si el nombre del item está vacío
      line_description = line["desc"].to_s.strip
      final_base_name = line_description.present? ? line_description : product_name

      # Características (Caracteristica2 a Caracteristica6)
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

      RouteExcelImportService.new(nil).send(:process_row, row_data)

      # Vincular qb_line_id al OrderItem recién creado/encontrado
      if line_id.present?
        order = Order.find_by(number: order_number)
        item = order&.order_items&.find_by(product: full_product)
        item&.update_columns(qb_line_id: line_id) if item && item.qb_line_id.blank?
      end

      Rails.logger.info "✅ Importado #{order_number} - #{full_product} - Cantidad: #{line["quantity"]}"
    end
  end

  def find_ext(ext_array, name)
    ext_array.find { |e| e["data_ext_name"] == name }&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    name.sub(/^\d+\s*/, "").sub(/^\((.+)\)$/, '\1').strip
  end
end
