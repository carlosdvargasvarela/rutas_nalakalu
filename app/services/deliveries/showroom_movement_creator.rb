module Deliveries
  class ShowroomMovementCreator
    def initialize(params:, current_user:)
      @params       = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        source      = Showroom.find(params.require(:source_showroom_id))
        destination = Showroom.find(params.require(:destination_showroom_id))

        client  = find_or_create_showroom_client
        seller  = find_or_create_showroom_seller(client)
        order   = create_showroom_order(client, seller, source, destination)
        address = destination.delivery_address

        raise ArgumentError, "La sala destino '#{destination.name}' no tiene dirección configurada." unless address

        items = build_items(order)
        raise ArgumentError, "Debes agregar al menos un producto al movimiento." if items.empty?

        @delivery = Delivery.new(
          movement_params.merge(
            delivery_type:        :showroom,
            status:               :ready_to_deliver,
            order:                order,
            delivery_address:     address,
            source_showroom:      source,
            destination_showroom: destination
          )
        )
        @delivery.delivery_items = items
        @delivery.save!
        @delivery
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("ShowroomMovementCreator error: #{e.message}")
      raise
    end

    private

    attr_reader :params, :current_user

    def find_or_create_showroom_client
      Client.find_or_create_by!(name: "NaLakalu Showrooms") do |c|
        c.email = "showrooms@nalakalu.com"
        c.phone = "0000-0000"
      end
    end

    def find_or_create_showroom_seller(client)
      Seller.find_or_create_by!(seller_code: "NALAKALU_SHOW") do |s|
        s.user = current_user
        s.name = "Movimientos Showroom"
      end
    end

    def create_showroom_order(client, seller, source, destination)
      number = "SHOW-#{source.code}-#{destination.code}-#{Time.current.strftime('%Y%m%d%H%M')}"
      client.orders.create!(
        number: number,
        seller: seller,
        status: :ready_for_delivery
      )
    end

    def build_items(order)
      items_attrs = params.dig(:delivery, :delivery_items_attributes)
      return [] unless items_attrs.present?

      items_attrs.values.filter_map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params.dig(:order_item_attributes, :product).blank?

        order_item = order.order_items.create!(
          product:  item_params[:order_item_attributes][:product],
          quantity: (item_params[:order_item_attributes][:quantity].presence || 1).to_i,
          status:   :ready
        )

        DeliveryItem.new(
          order_item:         order_item,
          quantity_delivered: (item_params[:quantity_delivered].presence || 1).to_i,
          status:             :confirmed
        )
      end
    end

    def movement_params
      params.require(:delivery).permit(
        :delivery_date,
        :contact_name,
        :contact_phone,
        :delivery_notes,
        :delivery_time_preference
      )
    end
  end
end
