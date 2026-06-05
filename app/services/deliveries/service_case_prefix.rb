# app/services/deliveries/service_case_prefix.rb
module Deliveries
  module ServiceCasePrefix
    def service_case_prefix_for(delivery_type)
      case delivery_type.to_s
      when "pickup_with_return", "only_pickup" then "Retiro - "
      when "return_delivery" then "Devolución - "
      when "onsite_repair" then "Reparación - "
      when "repair_pickup", "workspace_recoleccion" then "Recolección - "
      when "repair_return" then "Devolución - "
      else ""
      end
    end

    def duplicate_order_item_with_prefix(order_item, delivery_type)
      prefix = service_case_prefix_for(delivery_type)
      return order_item if prefix.blank?
      product_name = "#{prefix}#{order_item.product}"
      order_item.order.order_items.find_or_create_by!(product: product_name) do |oi|
        oi.quantity = order_item.quantity
        oi.notes    = order_item.notes
        oi.status   = order_item.status
      end
    end

    def build_order_item_with_prefix(order, attrs, delivery_type)
      prefix = service_case_prefix_for(delivery_type)
      product_name = "#{prefix}#{attrs[:product]}"
      order.order_items.find_or_create_by!(product: product_name) do |oi|
        oi.quantity = attrs[:quantity].presence || 1
        oi.notes    = attrs[:notes]
        oi.status   = :in_production
      end
    end
  end
end
