require 'roo'

class RouteExcelImportService
  def initialize(file_path)
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end

  def import_routes
    results = { success: 0, errors: [] }

    # Asumimos que la primera fila es encabezado
    (2..@spreadsheet.last_row).each do |row|
      begin
        data = extract_row_data(row)
        process_row(data)
        results[:success] += 1
      rescue => e
        results[:errors] << "Row #{row}: #{e.message}"
      end
    end

    results
  end

  private

  def extract_row_data(row)
    {
      delivery_date: @spreadsheet.cell(row, 'A'),
      team: @spreadsheet.cell(row, 'B'),
      order_number: @spreadsheet.cell(row, 'C')&.to_s,
      client_name: @spreadsheet.cell(row, 'D')&.to_s,
      product: @spreadsheet.cell(row, 'E')&.to_s,
      quantity: @spreadsheet.cell(row, 'F').to_i,
      seller_code: @spreadsheet.cell(row, 'G')&.to_s,
      place: @spreadsheet.cell(row, 'H')&.to_s,
      contact: @spreadsheet.cell(row, 'I')&.to_s,
      notes: @spreadsheet.cell(row, 'J')&.to_s,
      time_preference: @spreadsheet.cell(row, 'K')&.to_s
    }
  end

  def process_row(data)
    # Buscar o crear cliente
    client = Client.find_or_create_by!(name: data[:client_name])

    # Buscar o crear dirección de entrega
    address = client.delivery_addresses.find_or_create_by!(address: data[:place])

    # Buscar vendedor por seller_code
    seller = Seller.find_by(seller_code: data[:seller_code])
    raise "Seller with code #{data[:seller_code]} not found" unless seller

    # Buscar o crear pedido
    order = Order.find_or_create_by!(number: data[:order_number]) do |o|
      o.client = client
      o.seller = seller
      o.status = :ready_for_delivery
    end

    # Si el pedido existe pero el vendedor es diferente, actualizarlo
    if order.seller != seller
      order.update!(seller: seller)
    end

    # Buscar o crear item del pedido
    order_item = order.order_items.find_or_create_by!(product: data[:product]) do |item|
      item.quantity = data[:quantity]
      item.notes = data[:notes]
      item.status = :ready
    end

    # Si el item existe pero la cantidad o notas son diferentes, actualizarlas
    if order_item.quantity != data[:quantity] || order_item.notes != data[:notes]
      order_item.update!(quantity: data[:quantity], notes: data[:notes])
    end

    # Buscar o crear entrega
    delivery = order.deliveries.find_or_create_by!(delivery_date: data[:delivery_date], delivery_address: address) do |d|
      d.contact_name, d.contact_phone = parse_contact(data[:contact])
      d.delivery_time_preference = data[:time_preference]
      d.status = :scheduled
    end

    # Buscar o crear delivery_item
    service_case = data[:team].to_s.downcase.include?('c.s') || data[:team].to_s.downcase.include?('cs')
    delivery_item = delivery.delivery_items.find_or_create_by!(order_item: order_item) do |di|
      di.quantity_delivered = data[:quantity]
      di.status = :pending
      di.service_case = service_case
    end

    # Si el delivery_item existe pero la cantidad o el flag de service_case son diferentes, actualizarlas
    if delivery_item.quantity_delivered != data[:quantity] || delivery_item.service_case != service_case
      delivery_item.update!(quantity_delivered: data[:quantity], service_case: service_case)
    end
  end

  def parse_contact(contact_str)
    # Separa por "/" o por "-" si es necesario
    if contact_str&.include?('/')
      parts = contact_str.split('/')
      [parts[0].strip, parts[1].strip]
    elsif contact_str&.include?('-')
      parts = contact_str.split('-')
      [parts[0].strip, parts[1].strip]
    else
      [contact_str, nil]
    end
  end
end