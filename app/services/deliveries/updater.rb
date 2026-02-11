# app/services/deliveries/updater.rb
module Deliveries
  class Updater
    def initialize(delivery:, params:, current_user:)
      @delivery = delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        @order = find_or_resolve_order
        @client = @order.client
        @address = find_or_create_address(@client)

        # Aplicar la nueva dirección a la entrega antes de validar
        @delivery.delivery_address = @address

        # Actualizar / reconstruir los delivery_items si vienen en params
        update_delivery_items if delivery_params[:delivery_items_attributes].present?

        # Fecha "nueva" que se quiere para la entrega
        new_date = delivery_params[:delivery_date].presence || @delivery.delivery_date

        # Validar que no se dupliquen productos respecto a OTRAS entregas
        validate_no_duplicate_products!(
          order: @order,
          address: @address,
          date: new_date,
          delivery_items: @delivery.delivery_items,
          excluding_delivery: @delivery
        )

        # Finalmente, actualizar los demás atributos de la entrega
        @delivery.update!(delivery_params.except(:delivery_items_attributes, :delivery_address_id, :order_id))
      end

      @delivery
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("❌ Error en Deliveries::Updater: #{e.message}")
      raise e
    rescue ActiveRecord::RecordNotUnique
      raise StandardError, "Ya existe otra entrega con esa combinación de pedido, fecha y dirección."
    end

    private

    attr_reader :delivery, :params, :current_user

    def delivery_params
      params.require(:delivery).permit(
        :delivery_date,
        :delivery_address_id,
        :order_id,
        :contact_name,
        :contact_phone,
        :delivery_notes,
        :delivery_type,
        :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
          {order_item_attributes: [:id, :product, :quantity, :notes]}
        ]
      )
    end

    def normalize_id(raw)
      s = raw.to_s.strip
      return nil if s.blank? || s == "__new__"
      s
    end

    def find_or_resolve_order
      order_id = normalize_id(delivery_params[:order_id])
      return Order.find(order_id) if order_id.present?
      delivery.order
    end

    def find_or_create_address(client)
      addr_id = normalize_id(delivery_params[:delivery_address_id])

      if addr_id.present?
        addr = DeliveryAddress.find(addr_id)

        # 🔥 MEJORA: Permitir actualizar descripción sin crear dirección nueva
        if params[:delivery_address].present?
          update_attrs = address_params.dup

          # Solo actualizar descripción si cambió
          if update_attrs[:description].present? && update_attrs[:description] != addr.description
            addr.description = update_attrs[:description]
          end

          # Solo actualizar coordenadas si vienen nuevas
          lat = update_attrs[:latitude].to_s.strip
          lng = update_attrs[:longitude].to_s.strip

          if lat.present? && lng.present?
            new_lat = lat.to_f
            new_lng = lng.to_f

            # Solo actualizar si cambiaron significativamente (más de 0.0001 grados ≈ 11 metros)
            if (addr.latitude.to_f - new_lat).abs > 0.0001 || (addr.longitude.to_f - new_lng).abs > 0.0001
              addr.latitude = new_lat
              addr.longitude = new_lng
            end
          end

          # Actualizar plus_code si viene
          if update_attrs[:plus_code].present? && update_attrs[:plus_code] != addr.plus_code
            addr.plus_code = update_attrs[:plus_code]
          end

          # Actualizar address (texto) si viene
          if update_attrs[:address].present? && update_attrs[:address] != addr.address
            addr.address = update_attrs[:address]
          end

          addr.save! if addr.changed?
        end

        addr
      elsif params[:delivery_address]&.[](:address).present? ||
          (params[:delivery_address]&.[](:latitude).present? && params[:delivery_address]&.[](:longitude).present?)

        addr_attrs = address_params
        lat = addr_attrs[:latitude].to_s.strip
        lng = addr_attrs[:longitude].to_s.strip

        # Buscar dirección existente por coordenadas (con tolerancia de 11 metros)
        if lat.present? && lng.present?
          lat_f = lat.to_f
          lng_f = lng.to_f

          existing = client.delivery_addresses.where(
            "ABS(latitude - ?) < 0.0001 AND ABS(longitude - ?) < 0.0001",
            lat_f,
            lng_f
          ).first

          if existing
            # Actualizar descripción si viene nueva
            if addr_attrs[:description].present? && addr_attrs[:description] != existing.description
              existing.update!(description: addr_attrs[:description])
            end
            return existing
          end
        end

        # Buscar por dirección de texto
        address_text = addr_attrs[:address].to_s.strip
        if address_text.present?
          existing = client.delivery_addresses.find_by(address: address_text)
          if existing
            # Actualizar coordenadas y descripción si vienen
            updates = {}
            if lat.present? && lng.present?
              updates[:latitude] = lat.to_f
              updates[:longitude] = lng.to_f
            end
            if addr_attrs[:description].present?
              updates[:description] = addr_attrs[:description]
            end
            if addr_attrs[:plus_code].present?
              updates[:plus_code] = addr_attrs[:plus_code]
            end
            existing.update!(updates) if updates.any?
            return existing
          end
        end

        # Si no existe, crear nueva
        client.delivery_addresses.create!(addr_attrs)
      else
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debes seleccionar o ingresar una dirección."
      end
    end

    def address_params
      params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
    end

    # ==========================
    # DELIVERY ITEMS
    # ==========================

    def update_delivery_items
      processed_items = process_delivery_items_params(@order)
      delivery.delivery_items = processed_items
    end

    def process_delivery_items_params(order)
      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"

        if item_params[:id].present?
          update_existing_delivery_item(item_params)
        else
          build_new_delivery_item(order, item_params)
        end
      end.compact
    end

    def update_existing_delivery_item(item_params)
      di = DeliveryItem.find(item_params[:id])
      di.update!(
        quantity_delivered: item_params[:quantity_delivered] || di.quantity_delivered,
        service_case: item_params[:service_case] == "1",
        status: item_params[:status] || di.status,
        notes: item_params[:notes] || di.notes
      )

      update_order_item_if_needed(item_params[:order_item_attributes])
      di
    end

    def update_order_item_if_needed(oi_params)
      return unless oi_params.present? && oi_params[:id].present?

      order_item = OrderItem.find(oi_params[:id])
      permitted_update = {
        product: oi_params[:product] || order_item.product,
        quantity: oi_params[:quantity] || order_item.quantity,
        notes: oi_params[:notes] || order_item.notes
      }
      order_item.update!(permitted_update)
    end

    def build_new_delivery_item(order, item_params)
      return if item_params[:order_item_attributes].blank? || item_params[:order_item_attributes][:product].blank?

      order_item = find_or_create_order_item(order, item_params[:order_item_attributes])

      DeliveryItem.new(
        order_item: order_item,
        quantity_delivered: (item_params[:quantity_delivered].presence || 1).to_i,
        service_case: item_params[:service_case] == "1",
        status: :pending,
        notes: item_params[:notes]
      )
    end

    def find_or_create_order_item(order, oi_params)
      if oi_params[:id].present?
        order_item = OrderItem.find(oi_params[:id])
        order_item.update!(
          product: oi_params[:product] || order_item.product,
          quantity: oi_params[:quantity] || order_item.quantity,
          notes: oi_params[:notes] || order_item.notes
        )
        return order_item
      end

      existing_item = order.order_items.find_by(product: oi_params[:product])
      if existing_item
        existing_item.update!(
          quantity: oi_params[:quantity] || existing_item.quantity,
          notes: [existing_item.notes, oi_params[:notes]].compact.reject(&:blank?).join("; ")
        )
        existing_item
      else
        order.order_items.create!(
          product: oi_params[:product],
          quantity: (oi_params[:quantity].presence || 1).to_i,
          notes: oi_params[:notes],
          status: :in_production
        )
      end
    end

    # ==========================
    # VALIDACIÓN DE DUPLICADOS
    # ==========================

    def validate_no_duplicate_products!(order:, address:, date:, delivery_items:, excluding_delivery: nil)
      order_item_ids = delivery_items.map(&:order_item_id).compact.uniq
      return if order_item_ids.empty?

      blocked_statuses = %w[rescheduled cancelled archived]
      active_status_ids = Delivery.statuses.reject { |k, _| blocked_statuses.include?(k) }.values

      conflict_scope = DeliveryItem.joins(:delivery)
        .where(order_item_id: order_item_ids)
        .where(
          deliveries: {
            order_id: order.id,
            delivery_address_id: address.id,
            delivery_date: date,
            status: active_status_ids
          }
        )

      if excluding_delivery
        conflict_scope = conflict_scope.where.not(deliveries: {id: excluding_delivery.id})
      end

      return unless conflict_scope.exists?

      conflicting_order_item_ids = conflict_scope.select(:order_item_id).distinct.pluck(:order_item_id)
      product_names = OrderItem.where(id: conflicting_order_item_ids).pluck(:product).uniq

      message = "Ya existe otra entrega para este pedido, dirección y fecha con los siguientes productos: #{product_names.join(", ")}."
      raise ActiveRecord::RecordInvalid.new(delivery), message
    end
  end
end
