# app/services/deliveries/service_case_for_existing_creator.rb
module Deliveries
  class ServiceCaseForExistingCreator
    include Deliveries::ServiceCasePrefix

    def initialize(parent_delivery:, params:, current_user:)
      @parent_delivery = parent_delivery
      @params = params
      @current_user = current_user
    end

    # Devuelve la(s) entrega(s) creada(s).
    # Si es pickup_with_return -> devuelve [pickup_delivery, return_delivery]
    # Si no, devuelve [single_delivery]
    def call
      ActiveRecord::Base.transaction do
        base_date = safe_date(params.dig(:delivery, :delivery_date)) || Date.current
        dtype     = (params.dig(:delivery, :delivery_type).presence || :pickup).to_s

        address = if params.dig(:delivery, :delivery_address_id).present?
          DeliveryAddress.find(params[:delivery][:delivery_address_id])
        else
          parent_delivery.delivery_address
        end

        case dtype
        when "pickup_with_return"
          pickup_delivery = build_service_delivery(address, base_date, "pickup_with_return")
          pickup_delivery.delivery_items = build_service_items("pickup_with_return")
          pickup_delivery.save!

          return_date = base_date + 15.days
          return_delivery = build_service_delivery(address, return_date, "return_delivery")
          return_delivery.delivery_items = clone_items_with_type(pickup_delivery, "return_delivery")
          return_delivery.save!

          # Guarda en ivar por si al controller le interesa
          @created_deliveries = [pickup_delivery, return_delivery]
          pickup_delivery # DEVUELVE el principal
        else
          single_delivery = build_service_delivery(address, base_date, dtype)
          single_delivery.delivery_items = build_service_items(dtype)
          single_delivery.save!

          @created_deliveries = [single_delivery]
          single_delivery # DEVUELVE uno
        end
      end
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::ServiceCaseForExistingCreator: #{e.message}")
      raise e
    end

    # opcionalmente un reader
    attr_reader :created_deliveries

    private

    attr_reader :parent_delivery, :params, :current_user

    def service_case_params
      params.require(:delivery).permit(
        :delivery_date,
        :delivery_type,
        :delivery_notes,
        :delivery_time_preference,
        :delivery_address_id,
        :contact_name,
        :contact_phone,
        delivery_items_attributes: [
          :id,
          :order_item_id,
          :quantity_delivered,
          :status,
          :notes,
          :_destroy,
          order_item_attributes: [ :id, :product, :quantity, :notes ]
        ]
      )
    end

    def build_service_delivery(address, date, delivery_type)
      Delivery.new(
        order: parent_delivery.order,
        delivery_address: address,
        contact_name: params.dig(:delivery, :contact_name).presence || parent_delivery.contact_name,
        contact_phone: params.dig(:delivery, :contact_phone).presence || parent_delivery.contact_phone,
        delivery_notes: params.dig(:delivery, :delivery_notes).presence || parent_delivery.delivery_notes,
        delivery_time_preference: params.dig(:delivery, :delivery_time_preference).presence || parent_delivery.delivery_time_preference,
        delivery_date: date,
        status: :scheduled,
        delivery_type: delivery_type
      )
    end

    def build_service_items(delivery_type)
      # Si vienen items en params, procesarlos
      if params.dig(:delivery, :delivery_items_attributes).present?
        process_service_items_from_params(delivery_type)
      # Si viene flag copy_items, copiar del padre
      elsif params[:copy_items] == "1"
        copy_items_from_parent(delivery_type)
      else
        []
      end
    end

    def process_service_items_from_params(delivery_type)
      service_case_params[:delivery_items_attributes].values.map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params.dig(:order_item_attributes, :product).blank? && item_params[:order_item_id].blank?

        order_item = if item_params[:order_item_id].present?
          original = OrderItem.find(item_params[:order_item_id])
          duplicate_order_item_with_prefix(original, delivery_type)
        elsif item_params.dig(:order_item_attributes, :id).present?
          original = OrderItem.find(item_params.dig(:order_item_attributes, :id))
          duplicate_order_item_with_prefix(original, delivery_type)
        else
          # Crear nuevo con prefijo
          oi_attrs = item_params[:order_item_attributes]
          build_order_item_with_prefix(parent_delivery.order, oi_attrs, delivery_type)
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

    def copy_items_from_parent(delivery_type)
      parent_delivery.delivery_items.map do |item|
        # Duplicar el order_item con el prefijo correspondiente
        dup_oi = duplicate_order_item_with_prefix(item.order_item, delivery_type)

        DeliveryItem.new(
          order_item: dup_oi,
          quantity_delivered: item.quantity_delivered,
          notes: item.notes,
          service_case: true,
          status: :pending
        )
      end
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
