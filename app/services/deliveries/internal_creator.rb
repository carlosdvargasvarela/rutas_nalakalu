# app/services/deliveries/internal_creator.rb
module Deliveries
  class InternalCreator
    def initialize(params:, current_user:)
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        company_client = find_or_create_internal_client
        company_seller = find_or_create_internal_seller(company_client)

        order = create_internal_order(company_client, company_seller)
        address = find_or_create_internal_address(company_client)

        processed_items = process_internal_items(order)

        @delivery = Delivery.new(
          internal_delivery_params.merge(
            delivery_type: :internal_delivery,
            status: :ready_to_deliver,
            order: order,
            delivery_address: address
          )
        )
        @delivery.delivery_items = processed_items
        @delivery.save!

        @delivery
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("❌ Error en Deliveries::InternalCreator: #{e.message}")
      raise e
    end

    private

    attr_reader :params, :current_user

    def find_or_create_internal_client
      Client.find_or_create_by!(name: "NaLakalu Interno") do |client|
        client.email = "interno@nalakalu.com"
        client.phone = "0000-0000"
      end
    end

    def find_or_create_internal_seller(client)
      Seller.find_or_create_by!(seller_code: "NALAKALU_INT") do |seller|
        seller.user = current_user
        seller.name = "Logística Interna"
      end
    end

    def create_internal_order(client, seller)
      client.orders.create!(
        number: "MANDADO",
        seller: seller,
        status: :ready_for_delivery
      )
    end

    def find_or_create_internal_address(client)
      addr_params = params[:delivery_address]
      return nil unless addr_params.present?

      # PRIORIDAD DE TEXTO PARA LA DIRECCIÓN:
      # 1. El address que viene del mapa/autocomplete
      # 2. La descripción (referencia del chofer)
      # 3. El texto que el usuario escribió en el buscador (search_input)
      address_text = addr_params[:address].presence ||
        addr_params[:description].presence ||
        addr_params[:search_input].presence ||
        "Dirección manual"

      # PRIORIDAD PARA LA DESCRIPCIÓN:
      # Si no hay descripción, usamos lo que sea que el usuario haya escrito en el buscador
      description_text = addr_params[:description].presence ||
        addr_params[:search_input].presence ||
        "Sin descripción detallada"

      address = client.delivery_addresses.new(
        address: address_text,
        description: description_text,
        latitude: addr_params[:latitude].presence,
        longitude: addr_params[:longitude].presence,
        plus_code: addr_params[:plus_code].presence
      )

      # Guardar sin validaciones para permitir "Beraca" o cualquier texto
      address.save(validate: false)
      address
    end

    def process_internal_items(order)
      return [] unless params[:delivery].dig(:delivery_items_attributes)

      params[:delivery][:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params[:order_item_attributes].blank? || item_params[:order_item_attributes][:product].blank?

        order_item = order.order_items.create!(
          product: item_params[:order_item_attributes][:product],
          quantity: 1,
          status: :ready
        )

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: 1,
          status: :confirmed
        )
      end.compact
    end

    def internal_delivery_params
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
