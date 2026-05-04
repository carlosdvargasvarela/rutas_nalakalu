class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(xml_string)
    doc = Nokogiri::XML(xml_string)

    orders_processed = 0
    errors = []

    doc.xpath("//SalesOrderRet").each do |so_node|
      process_sales_order(so_node, errors)
      orders_processed += 1
    end

    Rails.logger.info "ProcessQuickbooksXmlJob: #{orders_processed} órdenes procesadas. Errores: #{errors.size}"
    errors.each { |e| Rails.logger.warn "  - #{e}" }
  end

  private

  def process_sales_order(so, errors)
    order_number = "PED-#{so.at_xpath("RefNumber")&.text&.strip}"
    due_date = so.at_xpath("DueDate")&.text&.strip
    client_name = so.at_xpath("CustomerRef/FullName")&.text&.strip
    address = so.at_xpath("ShipAddress/Addr1")&.text&.strip
    seller_code = so.at_xpath("SalesRepRef/FullName")&.text&.strip

    contact_entrega = so.at_xpath(".//DataExtRet[DataExtName='ContactoEntrega']/DataExtValue")&.text&.strip
    celular_entrega = so.at_xpath(".//DataExtRet[DataExtName='CelularEntrega']/DataExtValue")&.text&.strip
    full_contact = [contact_entrega, celular_entrega].select(&:present?).join(" / ")

    so.xpath("SalesOrderLineRet").each do |line|
      raw_product = line.at_xpath("ItemRef/FullName")&.text.to_s
      product_name = clean_product_name(raw_product)

      raw_qty = line.at_xpath("Quantity")&.text.to_s.tr(",", ".")
      quantity = raw_qty.to_f

      # Características 2-6 concatenadas con 4 espacios (ignorando vacíos)
      chars = (2..6).map do |i|
        line.at_xpath("DataExtRet[DataExtName='Caracteristica#{i}']/DataExtValue")&.text&.strip
      end.select(&:present?)

      full_product = [product_name, chars.join("    ")].select(&:present?).join("    ")

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
        notes: nil,
        time_preference: nil
      }

      # service = RouteExcelImportService.new(nil)
      # service.send(:process_row, row_data)
      Rails.logger.info "ProcessQuickbooksXmlJob: Procesando pedido  #{order_number}, producto '#{full_product}', cantidad #{quantity}."
    rescue => e
      errors << "#{order_number} / #{product_name}: #{e.message}"
      Rails.logger.error "ProcessQuickbooksXmlJob error en línea: #{e.message}"
    end
  end

  def clean_product_name(name)
    # "008000100 (Espejo de cuerpo entero)" → "Espejo de cuerpo entero"
    cleaned = name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
    cleaned.presence || name.strip
  end
end
