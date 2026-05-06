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
    ref_number = so["ref_number"].to_s.strip
    order_number = ref_number.start_with?("PED-") ? ref_number : "PED-#{ref_number}"

    existing = Order.find_by(number: order_number)

    # ── Órdenes pre-integración: solo vincular qb_txn_id, no tocar nada más ──
    if existing.present? && existing.qb_txn_id.blank?
      if qb_txn_id.present?
        existing.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
        Rails.logger.info "🔗 Vinculado #{order_number} con qb_txn_id: #{qb_txn_id} (pre-integración, sin modificar items)"
      else
        Rails.logger.info "⏭️ Saltando #{order_number}: pre-integración sin qb_txn_id"
      end
      return
    end

    # ── Orden ya importada por QB: si ya tiene qb_txn_id, no volver a procesar ──
    if existing.present? && existing.qb_txn_id.present?
      Rails.logger.info "⏭️ Saltando #{order_number}: ya fue importada desde QuickBooks (qb_txn_id: #{existing.qb_txn_id})"
      return
    end

    # ── Orden nueva: procesamiento completo ──
    due_date = so["due_date"]&.strip
    client_name = so.dig("customer_ref", "full_name")&.strip
    address = so.dig("ship_address", "addr1")&.strip.presence || "No especificada en QB"
    seller_code = so.dig("sales_rep_ref", "full_name")&.strip

    contact_name = find_ext(so["data_ext_ret"], "ContactoEntrega")
    contact_phone = find_ext(so["data_ext_ret"], "CelularEntrega")
    full_contact = [contact_name, contact_phone].select(&:present?).join(" / ")

    lines = so["sales_order_line_ret"]
    lines = [lines] if lines.is_a?(Hash)
    lines = [] if lines.blank?

    lines.each do |line|
      line_id = line["txn_line_id"]
      raw_item = line.dig("item_ref", "full_name").to_s
      product_name = clean_product_name(raw_item)

      raw_qty = line["quantity"].to_s.tr(",", ".")
      quantity = raw_qty.to_f

      chars = (1..6).map { |i| find_ext(line["data_ext_ret"], "Caracteristica#{i}") }.select(&:present?)

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
        notes: so["memo"],
        time_preference: nil
      }

      Rails.logger.info "ProcessQuickbooksXmlJob: Procesando #{order_number} | #{full_product} | Cant: #{quantity} | Cliente: #{client_name} | Vendedor: #{seller_code}"

      RouteExcelImportService.new(nil).send(:process_row, row_data)

      # ── Vincular qb_line_id usando el ID de QB como fuente de verdad ──
      if line_id.present?
        order = Order.find_by(number: order_number)
        item = order&.order_items&.find_by(qb_line_id: line_id)
        item ||= order&.order_items&.find_by(product: full_product, qb_line_id: nil)
        item&.update_columns(qb_line_id: line_id) if item&.qb_line_id.blank?
      end
    rescue => e
      Rails.logger.error "ProcessQuickbooksXmlJob: Error en línea #{order_number} / #{product_name}: #{e.message}"
    end

    # ── Registrar qb_txn_id en la orden una vez procesada ──
    order = Order.find_by(number: order_number)
    if order && qb_txn_id.present?
      order.update_columns(qb_txn_id: qb_txn_id, qb_updated_at: Time.current)
    end

    # ── Registrar evento de creación en DeliveryEvent ──
    order&.deliveries&.each do |delivery|
      DeliveryEvent.record(
        delivery: delivery,
        action: "created",
        actor: nil,
        payload: {
          source: "quickbooks",
          order_number: order_number,
          qb_txn_id: qb_txn_id
        }
      )
    end
  end

  def find_ext(data_ext_ret, target_name)
    entries =
      case data_ext_ret
      when Array then data_ext_ret
      when Hash then [data_ext_ret]
      else []
      end

    entry = entries.find { |item| item["data_ext_name"] == target_name }
    entry&.dig("data_ext_value")&.strip
  end

  def clean_product_name(name)
    cleaned = name.gsub(/^\d+\s*\(/, "").gsub(/\)$/, "").strip
    cleaned.presence || name.strip
  end
end
