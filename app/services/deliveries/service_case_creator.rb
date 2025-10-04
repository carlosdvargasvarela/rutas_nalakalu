# app/services/deliveries/service_case_creator.rb
module Deliveries
  class ServiceCaseCreator
    def initialize(params:, current_user:)
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        client  = find_or_create_client
        address = find_or_create_address(client)
        order   = find_or_create_order(client)

        processed_items = process_service_items(order)

        @delivery = Delivery.new(
          delivery_params.except(:delivery_items_attributes).merge(
            order: order,
            delivery_address: address,
            status: :scheduled,
            delivery_type: params[:delivery][:delivery_type] || :pickup
          )
        )
        @delivery.delivery_items = processed_items
        @delivery.save!

        @delivery
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

    def process_service_items(order)
      return [] unless delivery_params[:delivery_items_attributes]

      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params.dig(:order_item_attributes, :product).blank?

        order_item = if item_params[:order_item_id].present?
          OrderItem.find(item_params[:order_item_id])
        elsif item_params.dig(:order_item_attributes, :id).present?
          OrderItem.find(item_params.dig(:order_item_attributes, :id))
        else
          # ✅ FIX: Ahora sí pasamos quantity y notes al crear el OrderItem
          oi_attrs = item_params[:order_item_attributes]
          existing = order.order_items.find_by(product: oi_attrs[:product])

          existing || order.order_items.create!(
            product: oi_attrs[:product],
            quantity: oi_attrs[:quantity].presence || 1,
            notes: oi_attrs[:notes],
            status: :in_production
          )
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
  end
end
