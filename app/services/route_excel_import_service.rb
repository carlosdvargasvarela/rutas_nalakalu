require "roo"

class RouteExcelImportService
  def initialize(file_path = nil)
    @spreadsheet = Roo::Spreadsheet.open(file_path) if file_path
  end

  def import_routes
    raise "No se proporcionó archivo para importación masiva" unless @spreadsheet

    results = {success: 0, errors: []}
    (2..@spreadsheet.last_row).each do |row|
      data = extract_row_data(row)
      validation_errors = validate_row(data)
      if validation_errors.any?
        results[:errors] << "Fila #{row}: #{validation_errors.join(", ")}"
        next
      end
      process_row(data)
      results[:success] += 1
    rescue => e
      results[:errors] << "Fila #{row}: #{e.message}"
    end
    results
  end

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

  def process_row(data)
    order_number = safe_str(data[:order_number])
    client_name = safe_str(data[:client_name])
    product_name = safe_str(data[:product])
    seller_code = safe_str(data[:seller_code])
    place_text = safe_str(data[:place])
    contact_text = safe_str(data[:contact])
    notes_text = safe_str(data[:notes])
    time_pref_text = safe_str(data[:time_preference])
    qb_line_id = data[:qb_line_id].presence

    quantity = data[:quantity].to_i
    raise "Cantidad inválida" if quantity <= 0

    client = Client.find_or_create_by!(name: client_name)
    address = client.delivery_addresses.find_or_create_by!(address: place_text)

    if address.saved_change_to_id? || address.latitude.blank? || address.longitude.blank?
      refs = [contact_text, time_pref_text, notes_text].map(&:presence).compact.join(", ").presence
      address.update(description: refs) if refs.present?
      address.save(validate: false) if address.latitude.blank? || address.longitude.blank?
    end

    seller = Seller.find_by(seller_code: seller_code)
    raise "Vendedor con código #{seller_code} no encontrado" unless seller

    order = Order.find_or_create_by!(number: order_number) do |o|
      o.client = client
      o.seller = seller
      o.status = :in_production
    end
    order.update!(seller: seller) if order.seller_id != seller.id

    # ── OrderItem: buscar primero por qb_line_id, luego por producto ──
    order_item = nil
    order_item = order.order_items.find_by(qb_line_id: qb_line_id) if qb_line_id.present?
    order_item ||= order.order_items.find_or_initialize_by(product: product_name)

    combined_notes = if order_item.persisted? && notes_text.present? && notes_text != safe_str(order_item.notes)
      [safe_str(order_item.notes), notes_text].reject(&:blank?).uniq.join("; ")
    else
      notes_text.presence || order_item.notes
    end

    order_item.assign_attributes(
      product: product_name,
      quantity: quantity,
      notes: combined_notes,
      status: :in_production
    )
    order_item.qb_line_id ||= qb_line_id if qb_line_id.present?
    order_item.save!

    # ── Delivery ──
    delivery = order.deliveries
      .where(delivery_date: data[:delivery_date], delivery_address_id: address.id)
      .first_or_initialize

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

    # ── DeliveryItem ──
    service_case = safe_str(data[:team]).downcase.include?("c.s") ||
      safe_str(data[:team]).downcase.include?("cs")

    delivery_item = delivery.delivery_items.find_or_initialize_by(order_item: order_item)
    delivery_item.assign_attributes(
      quantity_delivered: quantity,
      status: :pending,
      service_case: service_case
    )
    delivery_item.save!
  end

  def extract_row_data(row)
    {
      delivery_date: @spreadsheet.cell(row, "A"),
      team: @spreadsheet.cell(row, "B"),
      order_number: @spreadsheet.cell(row, "C")&.to_s&.strip,
      client_name: @spreadsheet.cell(row, "D")&.to_s&.strip,
      product: @spreadsheet.cell(row, "E")&.to_s&.strip,
      quantity: @spreadsheet.cell(row, "F").to_i,
      seller_code: @spreadsheet.cell(row, "G")&.to_s&.strip,
      place: @spreadsheet.cell(row, "H")&.to_s&.strip,
      contact: @spreadsheet.cell(row, "I")&.to_s&.strip,
      notes: @spreadsheet.cell(row, "J")&.to_s&.strip,
      time_preference: @spreadsheet.cell(row, "K")&.to_s&.strip
    }
  end

  def parse_contact(contact_str)
    s = safe_str(contact_str)
    if s.include?("/")
      parts = s.split("/")
      [safe_str(parts[0]).presence, safe_str(parts[1]).presence]
    elsif s.include?("-")
      parts = s.split("-")
      [safe_str(parts[0]).presence, safe_str(parts[1]).presence]
    else
      [s.presence, nil]
    end
  end

  private

  def safe_str(v)
    v.to_s.strip
  end

  def blank_str?(v)
    safe_str(v).blank?
  end
end
