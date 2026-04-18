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
      "info"
    when "in_plan", "loaded_on_truck"
      "primary"
    when "in_route"
      "primary"

    # --- FINALIZADO EXITOSO (Verde) ---
    when "delivered"
      "success"

    # --- FINALIZADO CON ERROR / CANCELADO (Rojo) ---
    when "cancelled", "failed"
      "danger"

    # --- OTROS (Gris) ---
    when "archived"
      "secondary"
    else
      "secondary"
    end
  end

  def delivery_status_badge_class(status)
    color = delivery_status_color(status)
    "bg-#{color}-subtle text-#{color}-emphasis border border-#{color}-subtle"
  end

  def delivery_status_border_color(status)
    case delivery_status_color(status)
    when "warning" then "#ffc107"
    when "info" then "#0dcaf0"
    when "primary" then "#0d6efd"
    when "success" then "#198754"
    when "danger" then "#dc3545"
    when "secondary" then "#6c757d"
    else "#6c757d"
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
