module Deliveries
  class RepairServiceFromWorkspaceCreator
    include Deliveries::ServiceCasePrefix

    def initialize(original_delivery:, params:, current_user:)
      @original_delivery = original_delivery
      @params = params
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        date = Date.parse(params[:delivery][:delivery_date])

        ret = build_return_delivery(date)
        ret.delivery_items = build_items
        ret.save!

        prefix_original_items("repair_pickup")
        annotate_original(ret)

        DeliveryEvent.record(
          delivery: @original_delivery,
          action: "repair_service_created",
          actor: @current_user,
          payload: {
            new_delivery_id: ret.id,
            delivery_type: "repair_return",
            items_count: selected_items.count,
            delivery_date: ret.delivery_date.to_s
          }
        )

        DeliveryEvent.record(
          delivery: ret,
          action: "created",
          actor: @current_user,
          payload: {
            source_delivery_id: original_delivery.id,
            context: "repair_service",
            pickup_delivery_id: original_delivery.id
          }
        )

        ret
      end
    end

    private

    attr_reader :original_delivery, :params, :current_user

    def build_return_delivery(date)
      Delivery.new(
        order:            original_delivery.order,
        delivery_address: original_delivery.delivery_address,
        contact_name:     original_delivery.contact_name,
        contact_phone:    original_delivery.contact_phone,
        delivery_notes:   params.dig(:delivery, :delivery_notes).presence || auto_notes,
        delivery_date:    date,
        status:           :scheduled,
        delivery_type:    :repair_return
      )
    end

    def build_items
      selected_items.map do |item|
        DeliveryItem.new(
          order_item:         duplicate_order_item_with_prefix(item.order_item, "repair_return"),
          quantity_delivered: item.quantity_delivered,
          status:             :pending
        )
      end
    end

    def annotate_original(ret)
      products = selected_items.map { |i| i.order_item&.product }.compact.join(", ")
      note     = "Entrega de reparación agendada: #{products} — #{ret.delivery_date&.strftime('%d/%m/%Y')} (Pedido ##{original_delivery.order_number})"
      existing = original_delivery.delivery_notes.to_s.strip
      original_delivery.update!(delivery_notes: existing.present? ? "#{existing}\n#{note}" : note)
    end

    def auto_notes
      products = selected_items.map { |i| i.order_item&.product }.compact.join(", ")
      "Entrega de producto reparado: #{products} — Pedido ##{original_delivery.order_number}"
    end

    def prefix_original_items(prefix_type)
      selected_items.each do |item|
        prefixed = duplicate_order_item_with_prefix(item.order_item, prefix_type)
        item.update!(order_item: prefixed)
      end
    end

    def selected_items
      @selected_items ||= begin
        ids = Array(params[:item_ids]).flat_map { |id| id.to_s.split(",") }.map(&:to_i).reject(&:zero?)
        original_delivery.delivery_items.where(id: ids)
      end
    end
  end
end
