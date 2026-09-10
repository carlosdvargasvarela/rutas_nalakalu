module DeliveriesHelper
  # ============================================================================
  # COLORES DE ESTADO — Unificados y con distinción de flujo
  # ============================================================================

  def delivery_status_color(status)
    case status.to_s
    # --- FLUJO INICIAL / PENDIENTE (Amarillo) ---
    when "scheduled", "pending", "rescheduled"
      "warning"

    # --- FLUJO OPERATIVO (Azules) ---
    when "confirmed", "ready_to_deliver"
      "status-teal"
    when "in_plan", "loaded_on_truck"
      "status-blue"
    when "in_route"
      "status-blue"

    # --- FINALIZADO EXITOSO (Verde) ---
    when "delivered"
      "success"

    # --- FINALIZADO CON ERROR / CANCELADO (Rojo) ---
    when "cancelled", "failed"
      "danger"

    when "warehousing"
      "warehousing"

    # --- OTROS (Gris) ---
    when "archived"
      "status-taupe"
    else
      "status-taupe"
    end
  end

  def delivery_status_badge_class(status)
    color = delivery_status_color(status)
    "bg-#{color}-subtle text-#{color}-emphasis border border-#{color}-subtle"
  end

  def delivery_status_border_color(status)
    case delivery_status_color(status)
    when "warning" then "#B45309"
    when "status-teal" then "#5E8C8A"
    when "status-blue" then "#3F6B85"
    when "success" then "#4B7B4F"
    when "danger" then "#dc3545"
    when "status-taupe" then "#8C8074"
    when "warehousing" then "#6f42c1"
    else "#8C8074"
    end
  end

  # Mantenido por compatibilidad con vistas existentes
  def status_badge_class(delivery)
    delivery_status_badge_class(delivery.status)
  end

  # ============================================================================
  # WHATSAPP
  # ============================================================================

  def whatsapp_tracking_link(delivery)
    token = delivery.tracking_token
    return nil unless token

    url = public_tracking_url(token: token)
    message = "¡Hola! Soy de NaLakalu 🚚. Te comparto el enlace para que sigas tu entrega en tiempo real: #{url}"
    encoded_message = ERB::Util.url_encode(message)
    phone = delivery.contact_phone&.gsub(/\D/, "")

    "https://wa.me/#{phone}?text=#{encoded_message}"
  end
end
