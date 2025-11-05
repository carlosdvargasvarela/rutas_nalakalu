# app/services/route_excel_import_service.rb
require "roo"

class RouteExcelImportService
  def initialize(file_path = nil)
    @spreadsheet = Roo::Spreadsheet.open(file_path) if file_path
  end

  # Importa todas las filas del archivo (para uso en consola o importación masiva)
  def import_routes
    raise "No se proporcionó archivo para importación masiva" unless @spreadsheet

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
    errors << "El número de pedido es obligatorio" if blank_str?(data[:order_number])
    errors << "El nombre del cliente es obligatorio" if blank_str?(data[:client_name])
    errors << "El producto es obligatorio" if blank_str?(data[:product])
    errors << "La cantidad es obligatoria" if data[:quantity].blank? || data[:quantity].to_i <= 0
    errors << "El código de vendedor es obligatorio" if blank_str?(data[:seller_code])
    errors << "El lugar de entrega es obligatorio" if blank_str?(data[:place])
    errors
  end

  # Procesa una fila (hash de datos), creando o actualizando registros según sea necesario
  def process_row(data)
    # Normaliza strings para evitar nil.strip en cualquier parte del flujo
    order_number   = safe_str(data[:order_number])
    client_name    = safe_str(data[:client_name])
    product_name   = safe_str(data[:product])
    seller_code    = safe_str(data[:seller_code])
    place_text     = safe_str(data[:place])
    contact_text   = safe_str(data[:contact])
    notes_text     = safe_str(data[:notes])
    time_pref_text = safe_str(data[:time_preference])

    quantity = data[:quantity].to_i
    raise "Cantidad inválida" if quantity <= 0

    # Entidades base
    client = Client.find_or_create_by!(name: client_name)

    # Dirección: find_or_create_by para no duplicar; el geocoding enriquecido se dispara en el modelo al cambiar address
    address = client.delivery_addresses.find_or_create_by!(address: place_text)

    # Mejora de geocoding: si la dirección es nueva o no tiene coords, pasamos description con referencias
    if address.saved_change_to_id? || address.latitude.blank? || address.longitude.blank?
      refs = [ contact_text, time_pref_text, notes_text ].map { |v| v.presence }.compact.join(", ").presence
      if refs.present?
        # Solo actualizar description si aporta algo y no dispara geocoding de nuevo innecesariamente
        address.update(description: refs)
        # Nota: según tu modelo, la geocodificación solo corre si cambia address (before_validation). Esto NO fuerza re-geocodificar,
        # pero dejará guardadas referencias para una eventual edición o para el picker.
        # Si quisieras reintentar geocoding cuando no hay coords, puedes forzar un save si no hay lat/lng:
        if address.latitude.blank? || address.longitude.blank?
          address.save(validate: false)
        end
      end
    end

    seller = Seller.find_by(seller_code: seller_code)
    raise "Vendedor con código #{seller_code} no encontrado" unless seller

    order = Order.find_or_create_by!(number: order_number) do |o|
      o.client = client
      o.seller = seller
      o.status = :in_production
    end
    order.update!(seller: seller) if order.seller_id != seller.id

    # OrderItem
    order_item = order.order_items.find_or_initialize_by(product: product_name)

    combined_notes =
      if order_item.persisted? && notes_text.present? && notes_text != safe_str(order_item.notes)
        [ safe_str(order_item.notes), notes_text ].reject(&:blank?).uniq.join("; ")
      else
        notes_text.presence || order_item.notes
      end

    order_item.assign_attributes(
      quantity: quantity,         # Ya viene sumada desde el PrepareJob
      notes: combined_notes,
      status: :in_production
    )
    order_item.save!

    # Delivery
    delivery = order.deliveries.where(delivery_date: data[:delivery_date], delivery_address_id: address.id).first_or_initialize

    if delivery.new_record?
      contact_name, contact_phone = parse_contact(contact_text)

      delivery.assign_attributes(
        delivery_address: address,
        contact_name: contact_name,
        contact_phone: contact_phone,
        delivery_time_preference: time_pref_text,
        status: :scheduled
      )
      delivery.save!
    end

    # DeliveryItem
    # Detectar "caso de servicio" por contenido de team
    service_case = safe_str(data[:team]).downcase.include?("c.s") || safe_str(data[:team]).downcase.include?("cs")

    delivery_item = delivery.delivery_items.find_or_initialize_by(order_item: order_item)
    delivery_item.assign_attributes(
      quantity_delivered: quantity, # Ya viene sumada
      status: :pending,
      service_case: service_case
    )
    delivery_item.save!
  end

  # Extrae los datos de una fila del Excel (para importación masiva)
  def extract_row_data(row)
    {
      delivery_date:   @spreadsheet.cell(row, "A"),
      team:            @spreadsheet.cell(row, "B"),
      order_number:    @spreadsheet.cell(row, "C")&.to_s&.strip,
      client_name:     @spreadsheet.cell(row, "D")&.to_s&.strip,
      product:         @spreadsheet.cell(row, "E")&.to_s&.strip,
      quantity:        @spreadsheet.cell(row, "F").to_i,
      seller_code:     @spreadsheet.cell(row, "G")&.to_s&.strip,
      place:           @spreadsheet.cell(row, "H")&.to_s&.strip,
      contact:         @spreadsheet.cell(row, "I")&.to_s&.strip,
      notes:           @spreadsheet.cell(row, "J")&.to_s&.strip,
      time_preference: @spreadsheet.cell(row, "K")&.to_s&.strip
    }
  end

  # Utilidad para parsear el campo de contacto "Nombre / Tel" o "Nombre - Tel"
  def parse_contact(contact_str)
    s = safe_str(contact_str)
    if s.include?("/")
      parts = s.split("/")
      [ safe_str(parts[0]).presence, safe_str(parts[1]).presence ]
    elsif s.include?("-")
      parts = s.split("-")
      [ safe_str(parts[0]).presence, safe_str(parts[1]).presence ]
    else
      [ s.presence, nil ]
    end
  end

  private

  # Convierte a string, recorta espacios y puede devolver nil si queda vacío
  def norm_str(v)
    v.to_s.strip.presence
  end

  # Convierte a string y recorta; nunca devuelve nil (si queda vacío, retorna "")
  def safe_str(v)
    v.to_s.strip
  end

  def blank_str?(v)
    safe_str(v).blank?
  end
end
