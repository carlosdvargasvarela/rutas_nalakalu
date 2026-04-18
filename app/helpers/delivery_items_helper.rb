module DeliveryItemsHelper
  # Delega al helper unificado de deliveries
  # Así cualquier vista que use delivery_item_status_color sigue funcionando
  def delivery_item_status_color(status)
    delivery_status_color(status)
  end

  def delivery_item_status_badge_class(status)
    delivery_status_badge_class(status)
  end
end
