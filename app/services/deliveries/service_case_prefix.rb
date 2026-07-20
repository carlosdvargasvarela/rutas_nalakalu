# app/services/deliveries/service_case_prefix.rb
module Deliveries
  # ponytail: el nombre de producto ya no se prefija por tipo de servicio
  # (caso de servicio/recolección/retiro/...), queda igual al original.
  module ServiceCasePrefix
    def duplicate_order_item_with_prefix(order_item, _delivery_type = nil)
      order_item
    end

    def build_order_item_with_prefix(order, attrs, _delivery_type = nil)
      order.order_items.find_or_create_by!(product: attrs[:product].to_s.strip) do |oi|
        oi.quantity = attrs[:quantity].presence || 1
        oi.notes    = attrs[:notes]
        oi.status   = :in_production
      end
    end
  end
end
