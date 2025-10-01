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
          delivery_params.except(:delivery_items_attributes).merge(
            order: order,
            delivery_address: address,
            status: :ready_to_deliver
          )
        )
        @delivery.delivery_items = processed_items
        @delivery.save!

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
        :contact_name,
        :contact_phone,
        :delivery_notes,
        :delivery_type,
        :delivery_time_preference,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :service_case, :status, :notes, :_destroy,
          order_item_attributes: [ :id, :product, :quantity, :notes ]
        ]
      )
    end

    def find_or_create_client
      if params[:client_id].present?
        Client.find(params[:client_id])
      elsif params[:client].present?
        existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
        existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
        existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
      else
        raise ActiveRecord::RecordInvalid.new(Client.new), "Debe seleccionarse un cliente."
      end
    end

    def find_or_create_address(client)
      if params[:delivery]&.[](:delivery_address_id).present?
        DeliveryAddress.find(params[:delivery][:delivery_address_id])
      elsif params[:delivery_address].present?
        existing = client.delivery_addresses.find_by(address: params[:delivery_address][:address])
        existing || client.delivery_addresses.create!(
          params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code)
        )
      else
        raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debe seleccionarse o crearse una dirección."
      end
    end

    def find_or_create_order(client)
      if params[:delivery]&.[](:order_id).present?
        Order.find(params[:delivery][:order_id])
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

    def process_delivery_items(order)
      return [] unless delivery_params[:delivery_items_attributes]

      delivery_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"

        order_item = if item_params[:order_item_id].present?
          OrderItem.find(item_params[:order_item_id])
        else
          order.order_items.create!(
            product: item_params.dig(:order_item_attributes, :product),
            quantity: item_params.dig(:order_item_attributes, :quantity).presence || 1,
            notes: item_params.dig(:order_item_attributes, :notes),
            status: :in_production
          )
        end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: item_params[:quantity_delivered].presence || 1,
          service_case: item_params[:service_case] == "1",
          status: :pending
        )
      end.compact
    end
  end
end
