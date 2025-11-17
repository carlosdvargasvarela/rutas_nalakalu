# app/services/deliveries/creator.rb
module Deliveries
  class Creator
    def initialize(params:, current_user:)
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        client  = find_or_create_client
        address = find_or_create_address(client)
        order   = find_or_create_order(client)

        existing_delivery = Delivery.find_by(
          order: order,
          delivery_date: delivery_params[:delivery_date],
          delivery_address: address
        )

        return existing_delivery if existing_delivery.present?

        processed_items = process_delivery_items(order)

        @delivery = Delivery.new(
          delivery_params.except(:delivery_items_attributes, :delivery_address_id, :order_id).merge(
            order: order,
            delivery_address: address,
            status: :ready_to_deliver
          )
        )
        @delivery.delivery_items = processed_items
        @delivery.save!

        NotificationService.notify_current_week_delivery_created(@delivery, created_by: current_user.name)

        @delivery
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("❌ Error en Deliveries::Creator: #{e.message}")
      raise e
    end

    private

    attr_reader :params, :current_user

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
          { order_item_attributes: [ :id, :product, :quantity, :notes ] }
        ]
      )
    end

    def normalize_id(raw)
      s = raw.to_s.strip
      return nil if s.blank? || s == "__new__"
      s
    end

    def normalize_delivery_address_id(raw_id)
      normalize_id(raw_id)
    end

    def find_or_create_client
      # 1) Si viene un client_id (seleccionado desde combo), usar ese
      if params[:client_id].present?
        return Client.find(params[:client_id])
      end

      # 2) Si vienen datos de cliente en el formulario
      if params[:client].present?
        attrs = params.require(:client).permit(:name, :phone, :email)

        # Solo validación fuerte: que haya al menos nombre
        if attrs[:name].to_s.strip.blank?
          raise ActiveRecord::RecordInvalid.new(Client.new), "Debe indicarse el nombre del cliente."
        end

        # Intentar reutilizar por email/teléfono si existen
        existing = nil
        existing = Client.find_by(email: attrs[:email]) if attrs[:email].present?
        existing ||= Client.find_by(phone: attrs[:phone]) if attrs[:phone].present?

        return existing if existing

        # Si no existe, crear con lo que haya (nombre obligatorio, email/phone opcionales)
        return Client.create!(attrs)
      end

      # 3) Si no viene ni client_id ni params[:client], error
      raise ActiveRecord::RecordInvalid.new(Client.new), "Debe seleccionarse o crearse un cliente."
    end

    def find_or_create_address(client)
      raw_id = delivery_params[:delivery_address_id]
      normalized_id = normalize_delivery_address_id(raw_id)

      if normalized_id.present?
        return DeliveryAddress.find(normalized_id)
      end

      if params[:delivery_address].present?
        addr_attrs = params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)

        # Priorizar coordenadas: si vienen lat/lng, usarlas primero
        lat = addr_attrs[:latitude].to_s.strip
        lng = addr_attrs[:longitude].to_s.strip
        address_text = addr_attrs[:address].to_s.strip

        # Si hay coordenadas pero no hay dirección, error
        if lat.present? && lng.present? && address_text.blank?
          raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new),
                "Debe proporcionar una dirección junto con las coordenadas."
        end

        # Si no hay dirección en absoluto, error
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new),
              "Debe seleccionarse o crearse una dirección." if address_text.blank?

        # Buscar dirección existente por coordenadas primero (si están presentes)
        if lat.present? && lng.present?
          existing = client.delivery_addresses.find_by(
            latitude: lat.to_f.round(6),
            longitude: lng.to_f.round(6)
          )
          return existing if existing
        end

        # Buscar por dirección
        existing = client.delivery_addresses.find_by(address: address_text)
        return existing if existing

        # Crear nueva dirección con prioridad a coordenadas
        return client.delivery_addresses.create!(addr_attrs)
      end

      raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debe seleccionarse o crearse una dirección."
    end

    def find_or_create_order(client)
      order_id = normalize_id(delivery_params[:order_id])
      return Order.find(order_id) if order_id.present?

      order_number = params.dig(:order, :number).to_s.strip
      if order_number.present?
        existing = client.orders.find_by(number: order_number)
        return existing if existing

        seller_id = params[:seller_id].presence || current_user.seller&.id
        raise ActiveRecord::RecordInvalid.new(Order.new), "Debe indicar un vendedor para crear el pedido." if seller_id.blank?

        return client.orders.create!(
          number: order_number,
          seller_id: seller_id,
          status: :in_production
        )
      end

      raise ActiveRecord::RecordInvalid.new(Order.new), "Debe seleccionarse o crearse un pedido."
    end

    def process_delivery_items(order)
      return [] unless delivery_params[:delivery_items_attributes]

      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"

        order_item =
          if item_params[:order_item_id].present?
            OrderItem.find(item_params[:order_item_id])
          elsif item_params.dig(:order_item_attributes, :id).present?
            OrderItem.find(item_params.dig(:order_item_attributes, :id))
          else
            product_name = item_params.dig(:order_item_attributes, :product).to_s.strip
            next if product_name.blank?

            quantity = (item_params.dig(:order_item_attributes, :quantity).presence || 1).to_i
            notes = item_params.dig(:order_item_attributes, :notes)

            existing_order_item = order.order_items.find_by(product: product_name)
            if existing_order_item
              existing_order_item
            else
              order.order_items.create!(
                product: product_name,
                quantity: quantity,
                notes: notes,
                status: :in_production
              )
            end
          end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: (item_params[:quantity_delivered].presence || 1).to_i,
          service_case: item_params[:service_case] == "1",
          status: :pending
        )
      end.compact
    end
  end
end
