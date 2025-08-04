module NotificationsHelper
  def notification_link(notification)
    url = case notification.notifiable
    when Delivery
        delivery_path(notification.notifiable)
    when Order
        order_path(notification.notifiable)
    when DeliveryPlan
        delivery_plan_path(notification.notifiable)
    # Para cualquier otro modelo que no tenga ruta definida
    else
        nil
    end

    if url.present?
      link_to "Ver", url, class: "btn btn-sm btn-outline-secondary"
    else
      content_tag(:span, "Sin vista", class: "text-muted")
    end
  rescue StandardError
    # Si hay cualquier error generando la URL, mostrar texto neutro
    content_tag(:span, "Sin vista", class: "text-muted")
  end
end
