# app/helpers/deliveries_helper.rb
module DeliveriesHelper
  def status_badge_class(delivery)
    case delivery.status
    when "pending" then "bg-warning-subtle text-warning-emphasis border border-warning-subtle"
    when "confirmed" then "bg-success-subtle text-success-emphasis border border-success-subtle"
    when "error" then "bg-danger-subtle text-danger-emphasis border border-danger-subtle"
    when "scheduled" then "bg-info-subtle text-info-emphasis border border-info-subtle"
    when "delivered" then "bg-primary-subtle text-primary-emphasis border border-primary-subtle"
    else "bg-secondary-subtle text-secondary-emphasis"
    end
  end

  def whatsapp_tracking_link(delivery)
    token = delivery.tracking_token
    return nil unless token

    url = public_tracking_url(token: token)
    message = "¡Hola! Soy de NaLakalu 🚚. Te comparto el enlace para que sigas tu entrega en tiempo real: #{url}"

    # Codificar para URL
    encoded_message = ERB::Util.url_encode(message)

    # Si tiene teléfono, lo incluimos en el link
    phone = delivery.contact_phone&.gsub(/\D/, "") # Limpiar caracteres no numéricos

    "https://wa.me/#{phone}?text=#{encoded_message}"
  end
end
