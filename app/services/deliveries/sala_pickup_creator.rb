module Deliveries
  class SalaPickupCreator
    def initialize(original_delivery:, params:, current_user:)
      @original_delivery = original_delivery
      @params = params
      @current_user = current_user
    end

    def call
      validate_params!

      PaperTrail.request(whodunnit: @current_user.id.to_s) do
        ActiveRecord::Base.transaction do
          @address = find_or_create_address
          @pickup_delivery = create_pickup_delivery!
          create_pickup_items!
          update_original_delivery_notes!

          # 🔹 Registrar evento en la entrega original
          DeliveryEvent.record(
            delivery: @original_delivery,
            action: "sala_pickup_created",
            actor: @current_user,
            payload: {
              new_delivery_id: @pickup_delivery.id,
              pickup_date: @pickup_delivery.delivery_date.to_s,
              address: @address.description.presence || @address.address,
              items_count: @pickup_delivery.delivery_items.count
            }
          )

          # 🔹 Registrar evento en la nueva entrega de retiro en sala
          DeliveryEvent.record(
            delivery: @pickup_delivery,
            action: "created",
            actor: @current_user,
            payload: {
              source_delivery_id: @original_delivery.id,
              context: "sala_pickup"
            }
          )
        end
      end

      @pickup_delivery
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::SalaPickupCreator: #{e.message}")
      raise e
    end

    private

    attr_reader :original_delivery, :params, :current_user

    def validate_params!
      raise StandardError, "Debe seleccionar al menos un producto." if params[:item_ids].blank?

      delivery_date = params.dig(:delivery, :delivery_date)
      raise StandardError, "Debe seleccionar una fecha para el retiro en sala." if delivery_date.blank?

      addr = params[:delivery_address]
      if addr.blank? || addr[:latitude].blank? || addr[:longitude].blank?
        raise StandardError, "Debe indicar la ubicación de la sala en el mapa."
      end

      if delivery_date.to_date >= original_delivery.delivery_date
        raise StandardError, "La fecha del retiro debe ser anterior a la fecha de entrega del pedido (#{original_delivery.delivery_date.strftime("%d/%m/%Y")})."
      end
    end

    def create_pickup_delivery!
      Delivery.create!(
        order: original_delivery.order,
        delivery_address: @address,
        delivery_date: params.dig(:delivery, :delivery_date),
        contact_name: params.dig(:delivery, :contact_name).presence || "Encargado de Sala",
        contact_phone: params.dig(:delivery, :contact_phone),
        delivery_type: :only_pickup,
        status: :scheduled,
        delivery_notes: build_pickup_notes
      )
    end

    def find_or_create_address
      addr_params = params[:delivery_address]

      existing = DeliveryAddress.find_by(
        client_id: original_delivery.order.client_id,
        latitude: addr_params[:latitude],
        longitude: addr_params[:longitude]
      )

      return existing if existing.present?

      DeliveryAddress.create!(
        client_id: original_delivery.order.client_id,
        address: addr_params[:address],
        latitude: addr_params[:latitude],
        longitude: addr_params[:longitude],
        plus_code: addr_params[:plus_code],
        description: addr_params[:description]
      )
    end

    def create_pickup_items!
      items_to_copy = original_delivery.delivery_items.where(id: params[:item_ids])

      raise StandardError, "No se encontraron productos válidos para el retiro en sala." if items_to_copy.empty?

      items_to_copy.each do |original_item|
        DeliveryItem.create!(
          delivery: @pickup_delivery,
          order_item_id: original_item.order_item_id,
          quantity_delivered: original_item.quantity_delivered,
          status: :pending,
          service_case: original_item.service_case,
          notes: "Pendiente de #{Deliveries::Vocabulary.service_type_label("retiro").downcase} en sala antes de la entrega del #{original_delivery.delivery_date.strftime("%d/%m/%Y")}."
        )
      end

      # Marcar los items originales como ya procesados para sala pickup
      items_to_copy.update_all(sala_pickup_requested: true)
    end

    def update_original_delivery_notes!
      product_names = @pickup_delivery.delivery_items.map(&:product).join(", ")
      pickup_date = @pickup_delivery.delivery_date.strftime("%d/%m/%Y")

      retiro = Deliveries::Vocabulary.service_type_label("retiro")
      new_note = "\n[SISTEMA #{Date.current.strftime("%d/%m/%Y")}]: #{retiro} en sala programado para el #{pickup_date}. Productos a retirar: #{product_names}."

      original_delivery.update_column(
        :delivery_notes,
        "#{original_delivery.delivery_notes}#{new_note}"
      )
    end

    def build_pickup_notes
      base = "#{Deliveries::Vocabulary.service_type_label("retiro")} en sala — Pedido ##{original_delivery.order_number} (entrega original: #{original_delivery.delivery_date.strftime("%d/%m/%Y")})."
      extra = params[:delivery_notes].presence
      extra ? "#{base} #{extra}" : base
    end
  end
end
