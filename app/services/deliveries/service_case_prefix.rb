# app/services/deliveries/service_case_prefix.rb
module Deliveries
  module ServiceCasePrefix
    DELIVERY_TYPE_TO_SERVICE_TYPE = {
      "pickup_with_return" => "retiro",
      "only_pickup" => "retiro",
      "return_delivery" => "devolucion",
      "onsite_repair" => "reparacion",
      "repair_pickup" => "recoleccion",
      "workspace_recoleccion" => "recoleccion",
      "repair_return" => "devolucion"
    }.freeze

    def service_case_prefix_for(delivery_type)
      service_type = DELIVERY_TYPE_TO_SERVICE_TYPE[delivery_type.to_s]
      return "" unless service_type
      Deliveries::Vocabulary.service_type_prefix(service_type)
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
