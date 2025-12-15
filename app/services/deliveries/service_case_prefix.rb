# app/services/deliveries/service_case_prefix.rb
module Deliveries
  module ServiceCasePrefix
    def service_case_prefix_for(delivery_type)
      case delivery_type.to_s
      when "pickup_with_return", "only_pickup" then "Recogida - "
      when "return_delivery" then "Devolución - "
      when "onsite_repair" then "Reparación - "
      else ""
      end
    end

    def duplicate_order_item_with_prefix(order_item, delivery_type)
      prefix = service_case_prefix_for(delivery_type)
      return order_item if prefix.blank?
      order_item.order.order_items.create!(
        product: "#{prefix}#{order_item.product}",
        quantity: order_item.quantity,
        notes: order_item.notes,
        status: order_item.status
      )
    end

    def build_order_item_with_prefix(order, attrs, delivery_type)
      prefix = service_case_prefix_for(delivery_type)
      order.order_items.create!(
        product: "#{prefix}#{attrs[:product]}",
        quantity: attrs[:quantity].presence || 1,
        notes: attrs[:notes],
        status: :in_production
      )
    end
  end
end
