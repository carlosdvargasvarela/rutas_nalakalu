# app/services/route_excel_import_service.rb
require "roo"

class RouteExcelImportService
  def initialize(file_path = nil)
    @spreadsheet = Roo::Spreadsheet.open(file_path) if file_path
  end

  # Importa todas las filas del archivo (para uso en consola o importación masiva)
  def import_routes
    results = { success: 0, errors: [] }
    (2..@spreadsheet.last_row).each do |row|
      begin
        data = extract_row_data(row)
        validation_errors = validate_row(data)
        if validation_errors.any?
          results[:errors] << "Fila #{row}: #{validation_errors.join(', ')}"
          next
        end
        process_row(data)
        results[:success] += 1
      rescue => e
        results[:errors] << "Fila #{row}: #{e.message}"
      end
    end
    results
  end

  # Valida una fila (hash de datos), retorna array de errores
  def validate_row(data)
    errors = []
    errors << "La fecha de entrega es obligatoria" if data[:delivery_date].blank?
    errors << "El número de pedido es obligatorio" if data[:order_number].blank?
    errors << "El nombre del cliente es obligatorio" if data[:client_name].blank?
    errors << "El producto es obligatorio" if data[:product].blank?
    errors << "La cantidad es obligatoria" if data[:quantity].blank? || data[:quantity].to_i <= 0
    errors << "El código de vendedor es obligatorio" if data[:seller_code].blank?
    errors << "El lugar de entrega es obligatorio" if data[:place].blank?
    errors
  end

  # Procesa una fila (hash de datos), creando o actualizando registros según sea necesario
  def process_row(data)
    # Buscar o crear cliente
    client = Client.find_or_create_by!(name: data[:client_name])

    # Buscar o crear dirección de entrega
    address = client.delivery_addresses.find_or_create_by!(address: data[:place])

    # Buscar vendedor por seller_code
    seller = Seller.find_by(seller_code: data[:seller_code])
    raise "Vendedor con código #{data[:seller_code]} no encontrado" unless seller

    # Buscar o crear pedido
    order = Order.find_or_create_by!(number: data[:order_number]) do |o|
      o.client = client
      o.seller = seller
      o.status = :in_production
    end

    # Si el pedido existe pero el vendedor es diferente, actualizarlo
    order.update!(seller: seller) if order.seller != seller

    # ✅ OrderItem (blindaje: sin acumular)
    order_item = order.order_items.find_or_initialize_by(product: data[:product])
    if order_item.new_record?
      order_item.assign_attributes(
        quantity: data[:quantity],
        notes: data[:notes],
        status: :in_production
      )
      order_item.save!
    else
      combined_notes = if data[:notes].present? && data[:notes] != order_item.notes
        [ order_item.notes, data[:notes] ].compact.reject(&:blank?).uniq.join("; ")
      else
        order_item.notes || data[:notes]
      end

      order_item.update!(
        quantity: data[:quantity],
        notes: combined_notes
      )
    end

    # ✅ Delivery (blindaje: evitar duplicados con la misma orden, fecha y dirección)
    # aquí nos aseguramos de que no se creen dos deliveries "idénticos"
    delivery = order.deliveries
                    .joins(:delivery_address)
                    .where(delivery_date: data[:delivery_date], delivery_address_id: address.id)
                    .first_or_initialize

    if delivery.new_record?
      delivery.assign_attributes(
        delivery_address: address,
        contact_name: (parse_contact(data[:contact]).first),
        contact_phone: (parse_contact(data[:contact]).last),
        delivery_time_preference: data[:time_preference],
        status: :scheduled
      )
      delivery.save!
    end

    # ✅ DeliveryItem (blindaje: sin acumular)
    service_case = data[:team].to_s.downcase.include?("c.s") || data[:team].to_s.downcase.include?("cs")

    delivery_item = delivery.delivery_items.find_or_initialize_by(order_item: order_item)
    if delivery_item.new_record?
      delivery_item.assign_attributes(
        quantity_delivered: data[:quantity],
        status: :pending,
        service_case: service_case
      )
      delivery_item.save!
    else
      delivery_item.update!(
        quantity_delivered: data[:quantity],
        service_case: service_case
      )
    end
  end

  # Extrae los datos de una fila del Excel (para importación masiva)
  def extract_row_data(row)
    {
      delivery_date: @spreadsheet.cell(row, "A"),
      team: @spreadsheet.cell(row, "B"),
      order_number: @spreadsheet.cell(row, "C")&.to_s,
      client_name: @spreadsheet.cell(row, "D")&.to_s,
      product: @spreadsheet.cell(row, "E")&.to_s,
      quantity: @spreadsheet.cell(row, "F").to_i,
      seller_code: @spreadsheet.cell(row, "G")&.to_s,
      place: @spreadsheet.cell(row, "H")&.to_s,
      contact: @spreadsheet.cell(row, "I")&.to_s,
      notes: @spreadsheet.cell(row, "J")&.to_s,
      time_preference: @spreadsheet.cell(row, "K")&.to_s
    }
  end

  # Utilidad para parsear el campo de contacto
  def parse_contact(contact_str)
    if contact_str&.include?("/")
      parts = contact_str.split("/")
      [ parts[0].strip, parts[1].strip ]
    elsif contact_str&.include?("-")
      parts = contact_str.split("-")
      [ parts[0].strip, parts[1].strip ]
    else
      [ contact_str, nil ]
    end
  end
end
