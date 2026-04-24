# app/services/deliveries/service_case_from_workspace_creator.rb
module Deliveries
  class ServiceCaseFromWorkspaceCreator
    def initialize(original_delivery:, params:, current_user:)
      @original_delivery = original_delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        type = params[:delivery][:delivery_type]

        base = build_delivery(type, parsed_date)

        base.delivery_items = build_items(type)
        base.save!

        if type == "pickup_with_return"
          create_return_delivery(base)
        end

        base
      end
    end

    private

    attr_reader :original_delivery, :params, :current_user

    def build_delivery(type, date)
      Delivery.new(
        order: original_delivery.order,
        delivery_address: original_delivery.delivery_address,
        contact_name: original_delivery.contact_name,
        contact_phone: original_delivery.contact_phone,
        delivery_date: date,
        status: :scheduled,
        delivery_type: type
      )
    end

    def build_items(type)
      selected_items.map do |item|
        DeliveryItem.new(
          order_item: duplicate_item(item, type),
          quantity_delivered: item.quantity_delivered,
          service_case: true,
          status: :pending
        )
      end
    end

    def selected_items
      ids = Array(params[:item_ids]).flat_map { |id| id.to_s.split(",") }.map(&:to_i).reject(&:zero?)
      original_delivery.delivery_items.where(id: ids)
    end

    def duplicate_item(item, type)
      prefix = case type
      when "only_pickup" then "Recogida - "
      when "return_delivery" then "Devolución - "
      else ""
      end

      original_delivery.order.order_items.create!(
        product: "#{prefix}#{item.order_item.product}",
        quantity: item.order_item.quantity
      )
    end

    def create_return_delivery(pickup)
      Delivery.create!(
        order: pickup.order,
        delivery_address: pickup.delivery_address,
        delivery_date: pickup.delivery_date + 15.days,
        delivery_type: :return_delivery,
        status: :scheduled,
        contact_name: pickup.contact_name,
        contact_phone: pickup.contact_phone
      )
    end

    def parsed_date
      Date.parse(params[:delivery][:delivery_date])
    end
  end
end
