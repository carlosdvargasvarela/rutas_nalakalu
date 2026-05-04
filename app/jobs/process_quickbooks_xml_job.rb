class ProcessQuickbooksXmlJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(xml_string)
    doc = Nokogiri::XML(xml_string)

    # Buscamos cada SalesOrderRet en el XML
    doc.xpath("//SalesOrderRet").each do |so_node|
      process_sales_order(so_node)
    end
  end

  private

  def process_sales_order(so)
    order_number = "PED-#{so.at_xpath("RefNumber")&.text}"
    due_date = so.at_xpath("DueDate")&.text
    client_name = so.at_xpath("CustomerRef/FullName")&.text
    address = so.at_xpath("ShipAddress/Addr1")&.text

    contact_entrega = so.at_xpath("//DataExtRet[DataExtName='ContactoEntrega']/DataExtValue")&.text
    celular_entrega = so.at_xpath("//DataExtRet[DataExtName='CelularEntrega']/DataExtValue")&.text
    full_contact = [contact_entrega, celular_entrega].compact.join(" / ")

    # Procesamos los items (líneas)
    so.xpath("SalesOrderLineRet").each do |line|
      # Extraemos el nombre del producto y limpiamos SKU/Paréntesis
      raw_product = line.at_xpath("ItemRef/FullName")&.text || ""
      product_name = clean_product_name(raw_product)

      # Limpiamos y normalizamos la cantidad (convirtiendo "0,5" a "0.5")
      raw_qty = line.at_xpath("Quantity")&.text || "0"
      quantity = raw_qty.tr(",", ".").to_f

      # Extraemos características (DataExtRet) y las concatenamos con 4 espacios
      chars = []
      (2..6).each do |i|
        val = line.at_xpath("DataExtRet[DataExtName='Caracteristica#{i}']/DataExtValue")&.text
        chars << val if val.present?
      end

      full_product_description = [product_name, chars.join("    ")].reject(&:blank?).join("    ")

      # Construimos el hash idéntico al que espera tu RouteExcelImportService
      row_data = {
        delivery_date: due_date,
        order_number: order_number,
        client_name: client_name,
        product: full_product_description,
        quantity: quantity,
        place: address,
        contact: full_contact,
        seller_code: so.at_xpath("SalesRepRef/FullName")&.text,
        team: nil,
        notes: nil,
        time_preference: nil
      }

      # LLAMADA A TU SERVICIO EXISTENTE
      # Reutilizamos tu lógica de base de datos
      # service = RouteExcelImportService.new(nil) # Pasamos nil porque no hay archivo físico
      Rails.logger.info "ProcessQuickbooksXmlJob - Procesando orden #{order_number} para cliente #{client_name} con producto #{product_name} y cantidad #{quantity}"
      # service.send(:process_row, row_data) # Usamos send si el método es privado
    end
  end

  def clean_product_name(name)
    # Elimina SKU inicial "0000 (Nombre)" -> "Nombre"
    name.gsub(/^\d+\s*\((.*)\)/, '\1').gsub(/[()]/, "").strip
  end
end
