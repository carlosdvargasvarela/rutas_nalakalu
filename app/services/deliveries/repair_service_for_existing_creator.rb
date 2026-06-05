# app/services/deliveries/repair_service_for_existing_creator.rb
module Deliveries
  class RepairServiceForExistingCreator
    include Deliveries::ServiceCasePrefix

    def initialize(parent_delivery:, params:, current_user:)
      @parent_delivery = parent_delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        base_date = safe_date(params.dig(:delivery, :delivery_date)) || Date.current
        dtype = params.dig(:delivery, :delivery_type).to_s

        raw_id = params.dig(:delivery, :delivery_address_id).to_s
        normalized = (raw_id.present? && raw_id != "__new__") ? raw_id : nil
        address = normalized.present? ? DeliveryAddress.find(normalized) : parent_delivery.delivery_address

        case dtype
        when "repair_with_return"
          pickup = build_repair_delivery(address, base_date, "repair_pickup")
          pickup.delivery_items = build_repair_items("repair_pickup")
          pickup.save!

          return_date = base_date + 15.days
          ret = build_repair_delivery(address, return_date, "repair_return")
          ret.delivery_items = clone_items_with_type(pickup, "repair_return")
          ret.save!

          @created_deliveries = [pickup, ret]
          pickup
        else
          single = build_repair_delivery(address, base_date, dtype)
          single.delivery_items = build_repair_items(dtype)
          single.save!

          @created_deliveries = [single]
          single
        end
      end
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::RepairServiceForExistingCreator: #{e.message}")
      raise e
    end

    attr_reader :created_deliveries

    private

    attr_reader :parent_delivery, :params, :current_user

    def repair_params
      params.require(:delivery).permit(
        :delivery_date,
        :delivery_type,
        :delivery_notes,
        :delivery_time_preference,
        :delivery_address_id,
        :contact_name,
        :contact_phone,
        delivery_items_attributes: [
          :id, :order_item_id, :quantity_delivered, :status, :notes, :_destroy,
          order_item_attributes: [:id, :product, :quantity, :notes]
        ]
      )
    end

    def build_repair_delivery(address, date, delivery_type)
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

    def build_repair_items(delivery_type)
      if params.dig(:delivery, :delivery_items_attributes).present?
        process_items_from_params(delivery_type)
      elsif params[:copy_items] == "1"
        copy_items_from_parent(delivery_type)
      else
        []
      end
    end

    def process_items_from_params(delivery_type)
      repair_params[:delivery_items_attributes].values.filter_map do |item_params|
        next if item_params[:_destroy] == "1"
        next if item_params.dig(:order_item_attributes, :product).blank? && item_params[:order_item_id].blank?

        order_item = if item_params[:order_item_id].present?
          duplicate_order_item_with_prefix(OrderItem.find(item_params[:order_item_id]), delivery_type)
        elsif item_params.dig(:order_item_attributes, :id).present?
          duplicate_order_item_with_prefix(OrderItem.find(item_params.dig(:order_item_attributes, :id)), delivery_type)
        else
          oi_attrs = item_params[:order_item_attributes]
          next if oi_attrs.blank? || oi_attrs[:product].to_s.strip.blank?
          build_order_item_with_prefix(parent_delivery.order, oi_attrs, delivery_type)
        end

        DeliveryItem.new(
          order_item: order_item,
          quantity_delivered: item_params[:quantity_delivered].presence || 1,
          notes: item_params[:notes],
          status: :pending
        )
      end
    end

    def copy_items_from_parent(delivery_type)
      parent_delivery.delivery_items.map do |item|
        DeliveryItem.new(
          order_item: duplicate_order_item_with_prefix(item.order_item, delivery_type),
          quantity_delivered: item.quantity_delivered,
          notes: item.notes,
          status: :pending
        )
      end
    end

    def clone_items_with_type(source_delivery, target_type)
      source_delivery.delivery_items.map do |di|
        DeliveryItem.new(
          order_item: duplicate_order_item_with_prefix(di.order_item, target_type),
          quantity_delivered: di.quantity_delivered,
          notes: di.notes,
          status: :pending
        )
      end
    end

    def safe_date(str)
      str.present? ? Date.parse(str) : nil
    end
  end
end
