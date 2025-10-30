# app/services/deliveries/service_case_creator.rb
module Deliveries
  class ServiceCaseCreator
    include Deliveries::ServiceCasePrefix

    def initialize(params:, current_user:)
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        client  = find_or_create_client
        address = find_or_create_address(client)
        order   = find_or_create_order(client)

        base_date = safe_date(delivery_params[:delivery_date]) || Date.current
        dtype     = (delivery_params[:delivery_type].presence || :pickup).to_s

        case dtype
        when "pickup_with_return"
          pickup_delivery  = build_service_delivery(order, address, base_date, "pickup_with_return")
          pickup_delivery.delivery_items = process_service_items(order, "pickup_with_return")
          pickup_delivery.save!

          return_date     = base_date + 15.days
          return_delivery = build_service_delivery(order, address, return_date, "return_delivery")
          return_delivery.delivery_items = clone_items_with_type(pickup_delivery, "return_delivery")
          return_delivery.save!

          [ pickup_delivery, return_delivery ]
        else
          single_delivery = build_service_delivery(order, address, base_date, dtype)
          single_delivery.delivery_items = process_service_items(order, dtype)
          single_delivery.save!
          [ single_delivery ]
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("❌ Error en Deliveries::ServiceCaseCreator: #{e.message}")
      raise e
    end

    private

    attr_reader :params, :current_user

    # Strong params SOLO para la rama :delivery
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
          :id, :order_item_id, :quantity_delivered, :status, :notes, :_destroy,
          order_item_attributes: [ :id, :product, :quantity, :notes ]
        ]
      )
    end

    def normalize_id(raw)
      id = raw.to_s.strip
      return nil if id.blank? || id == "__new__"
      id
    end

    def find_or_create_client
      # client_id viene a nivel raíz (no dentro de :client), por eso no es parte de strong params
      if params[:client_id].present?
        Client.find(params[:client_id])
      elsif params[:client].present? && (params[:client][:email].present? || params[:client][:phone].present?)
        existing = nil
        existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
        existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
        existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
      else
        raise ActiveRecord::RecordInvalid.new(Client.new), "Debe seleccionarse un cliente."
      end
    end

    def find_or_create_address(client)
      raw_id = delivery_params[:delivery_address_id]
      address_id = normalize_id(raw_id)

      if address_id.present?
        return DeliveryAddress.find(address_id)
      end

      if params[:delivery_address].present?
        addr_attrs = params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
        address_text = addr_attrs[:address].to_s.strip
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debe seleccionarse o crearse una dirección." if address_text.blank?

        existing = client.delivery_addresses.find_by(address: address_text)
        return existing if existing

        return client.delivery_addresses.create!(addr_attrs)
      end

      raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debe seleccionarse o crearse una dirección."
    end

    def find_or_create_order(client)
      # 1) Si recibimos un ID válido de pedido, usar ese
      order_id = normalize_id(delivery_params[:order_id])
      if order_id.present?
        return Order.find(order_id)
      end

      # 2) Si viene un número de pedido, buscar o crear dentro del cliente
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

      # 3) Si no hay ni ID ni número, no podemos continuar
      raise ActiveRecord::RecordInvalid.new(Order.new), "Debe seleccionarse o crearse un pedido."
    end

    def build_service_delivery(order, address, date, delivery_type)
      Delivery.new(
        order: order,
        delivery_address: address,
        contact_name: delivery_params[:contact_name],
        contact_phone: delivery_params[:contact_phone],
        delivery_notes: delivery_params[:delivery_notes],
        delivery_time_preference: delivery_params[:delivery_time_preference],
        delivery_date: date,
        status: :scheduled,
        delivery_type: delivery_type
      )
    end

    def process_service_items(order, delivery_type)
      attrs = delivery_params[:delivery_items_attributes]
      return [] unless attrs.present?

      attrs.values.filter_map do |item_params|
        next if item_params[:_destroy] == "1"

        # Si viene order_item_id, duplicar con prefijo para el tipo de servicio
        if item_params[:order_item_id].present?
          original = OrderItem.find(item_params[:order_item_id])
          order_item = duplicate_order_item_with_prefix(original, delivery_type)

        # Si viene order_item_attributes.id, también duplicar
        elsif item_params.dig(:order_item_attributes, :id).present?
          original = OrderItem.find(item_params.dig(:order_item_attributes, :id))
          order_item = duplicate_order_item_with_prefix(original, delivery_type)

        # Si viene un nuevo producto por atributos, crear uno asociado al order
        else
          oi_attrs = item_params[:order_item_attributes] || {}
          product  = oi_attrs[:product].to_s.strip
          next if product.blank?

          order_item = build_order_item_with_prefix(order, oi_attrs, delivery_type)
        end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: (item_params[:quantity_delivered].presence || 1).to_i,
          notes: item_params[:notes],
          service_case: true,
          status: :pending
        )
      end
    end

    def clone_items_with_type(source_delivery, target_delivery_type)
      source_delivery.delivery_items.map do |di|
        dup_oi = duplicate_order_item_with_prefix(di.order_item, target_delivery_type)
        DeliveryItem.new(
          order_item: dup_oi,
          quantity_delivered: di.quantity_delivered,
          notes: di.notes,
          service_case: true,
          status: :pending
        )
      end
    end

    def safe_date(str)
      str.present? ? Date.parse(str) : nil
    end
  end
end
