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

        return_delivery = nil
        if type == "pickup_with_return"
          return_delivery = create_return_delivery(base)
        end

        # 🔹 Registrar evento en la entrega original
        created_ids = [base.id, return_delivery&.id].compact
        DeliveryEvent.record(
          delivery: @original_delivery,
          action: "service_case_created",
          actor: @current_user,
          payload: {
            new_delivery_ids: created_ids,
            delivery_type: type,
            items_count: selected_items.count,
            delivery_date: base.delivery_date.to_s
          }
        )

        # 🔹 Registrar evento en la nueva entrega
        DeliveryEvent.record(
          delivery: base,
          action: "created",
          actor: @current_user,
          payload: {
            source_delivery_id: @original_delivery.id,
            context: "service_case",
            delivery_type: type
          }
        )

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
      @selected_items ||= begin
        ids = Array(params[:item_ids]).flat_map { |id| id.to_s.split(",") }.map(&:to_i).reject(&:zero?)
        original_delivery.delivery_items.where(id: ids)
      end
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
      ret = Delivery.create!(
        order: pickup.order,
        delivery_address: pickup.delivery_address,
        delivery_date: pickup.delivery_date + 15.days,
        delivery_type: :return_delivery,
        status: :scheduled,
        contact_name: pickup.contact_name,
        contact_phone: pickup.contact_phone
      )

      # 🔹 Registrar evento en la entrega de devolución
      DeliveryEvent.record(
        delivery: ret,
        action: "created",
        actor: @current_user,
        payload: {
          source_delivery_id: @original_delivery.id,
          context: "service_case_return",
          pickup_delivery_id: pickup.id
        }
      )

      ret
    end

    def parsed_date
      Date.parse(params[:delivery][:delivery_date])
    end
  end
end
