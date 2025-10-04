# app/services/deliveries/service_case_creator.rb
module Deliveries
  class ServiceCaseCreator
    include Deliveries::ServiceCasePrefix

    def initialize(params:, current_user:)
      @params = params
      @current_user = current_user
    end

    # Devuelve la(s) entrega(s) creada(s).
    # Si es pickup_with_return -> devuelve [pickup_delivery, return_delivery]
    # Si no, devuelve [single_delivery]
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

          return_date      = base_date + 15.days
          return_delivery  = build_service_delivery(order, address, return_date, "return_delivery")
          # Los mismos productos pero con prefijo de devolución
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

    def find_or_create_client
      if params[:client_id].present?
        Client.find(params[:client_id])
      elsif params[:client].present? && (params[:client][:email].present? || params[:client][:phone].present?)
        existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
        existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
        existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
      else
        raise ActiveRecord::RecordInvalid.new(Client.new), "Debe seleccionarse un cliente."
      end
    end

    def find_or_create_address(client)
      if delivery_params[:delivery_address_id].present?
        DeliveryAddress.find(delivery_params[:delivery_address_id])
      elsif params[:delivery_address].present? && params[:delivery_address][:address].present?
        existing = client.delivery_addresses.find_by(address: params[:delivery_address][:address])
        existing || client.delivery_addresses.create!(
          params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
        )
      else
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debe seleccionarse o crearse una dirección."
      end
    end

    def find_or_create_order(client)
      if delivery_params[:order_id].present?
        Order.find(delivery_params[:order_id])
      elsif params[:order]&.[](:number).present?
        existing = client.orders.find_by(number: params[:order][:number])
        existing || client.orders.create!(
          number: params[:order][:number],
          seller_id: params[:seller_id] || current_user.seller&.id,
          status: :in_production
        )
      else
        raise ActiveRecord::RecordInvalid.new(Order.new), "Debe seleccionarse o crearse un pedido."
      end
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
      return [] unless delivery_params[:delivery_items_attributes]

      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params.dig(:order_item_attributes, :product).blank? && item_params[:order_item_id].blank?

        order_item = if item_params[:order_item_id].present?
          original = OrderItem.find(item_params[:order_item_id])
          duplicate_order_item_with_prefix(original, delivery_type)
        elsif item_params.dig(:order_item_attributes, :id).present?
          original = OrderItem.find(item_params.dig(:order_item_attributes, :id))
          duplicate_order_item_with_prefix(original, delivery_type)
        else
          oi_attrs = item_params[:order_item_attributes]
          build_order_item_with_prefix(order, oi_attrs, delivery_type)
        end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: item_params[:quantity_delivered].presence || 1,
          notes: item_params[:notes],
          service_case: true,
          status: :pending
        )
      end.compact
    end

    # Clona los items de una entrega a otra cambiando el tipo (para prefijos correctos)
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
