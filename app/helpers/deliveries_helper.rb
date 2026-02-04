# app/helpers/deliveries_helper.rb
module DeliveriesHelper
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
