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

        client = find_or_create_showroom_client
        seller = find_or_create_showroom_seller(client)
        order  = create_showroom_order(client, seller, source, destination)
        items  = build_items(order)

        raise ArgumentError, "Debes agregar al menos un producto al movimiento." if items.empty?

        if inter_sala?(source, destination)
          create_inter_sala_deliveries(source, destination, order, items)
        else
          address = destination.delivery_address
          raise ArgumentError, "La sala destino '#{destination.name}' no tiene dirección configurada." unless address

          delivery = Delivery.new(
            movement_params.merge(
              delivery_type:        :showroom,
              status:               :ready_to_deliver,
              order:                order,
              delivery_address:     address,
              source_showroom:      source,
              destination_showroom: destination
            )
          )
          delivery.delivery_items = items
          delivery.save!
          [delivery]
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("ShowroomMovementCreator error: #{e.message}")
      raise
    end

    private

    attr_reader :params, :current_user

    def inter_sala?(source, destination)
      !source.is_main && !destination.is_main
    end

    def create_inter_sala_deliveries(source, destination, order, items)
      pickup_address   = source.delivery_address
      delivery_address = destination.delivery_address

      raise ArgumentError, "La sala origen '#{source.name}' no tiene dirección configurada." unless pickup_address
      raise ArgumentError, "La sala destino '#{destination.name}' no tiene dirección configurada." unless delivery_address

      date_destination = params.require(:delivery)[:delivery_date_destination].presence
      raise ArgumentError, "Debe seleccionar la fecha de entrega a sala destino." if date_destination.blank?

      pickup_date = movement_params[:delivery_date]
      if pickup_date.present? && date_destination.to_date <= pickup_date.to_date
        raise ArgumentError, "La fecha de entrega a sala destino debe ser posterior a la fecha de recolección."
      end

      base = movement_params

      # Entrega 1: recolección en sala origen
      pickup = Delivery.new(
        base.merge(
          delivery_type:        :showroom,
          status:               :ready_to_deliver,
          order:                order,
          delivery_address:     pickup_address,
          source_showroom:      source,
          destination_showroom: nil,
          delivery_notes:       "#{Deliveries::Vocabulary.service_type_label("recoleccion")} de productos"
        )
      )
      pickup.delivery_items = items
      pickup.save!

      # Entrega 2: entrega a sala destino
      items_for_delivery = items.map do |di|
        DeliveryItem.new(
          order_item:         di.order_item,
          quantity_delivered: di.quantity_delivered,
          status:             :confirmed
        )
      end

      delivery = Delivery.new(
        base.merge(
          delivery_type:        :showroom,
          status:               :scheduled,
          order:                order,
          delivery_address:     delivery_address,
          source_showroom:      source,
          destination_showroom: destination,
          delivery_date:        date_destination,
          delivery_notes:       "#{Deliveries::Vocabulary.service_type_label("entrega")} de productos"
        )
      )
      delivery.delivery_items = items_for_delivery
      delivery.save!

      [pickup, delivery]
    end

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
      number = "entre_sala_#{source.code}_#{destination.code}"
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
