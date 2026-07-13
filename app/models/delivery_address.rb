# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  include Geocodable

  has_paper_trail
  belongs_to :client

  # ============================================================================
  # VALIDACIÓN DE DIRECCIONES PARA REPORTES
  # ============================================================================

  # Palabras/frases que indican dirección inválida
  INVALID_ADDRESS_KEYWORDS = [
    "pendiente", "por definir", "por definir dirección", "por definir dir",
    "pend", "tbd", "n/a", "sin dirección", "sin direccion", "no definido",
    "a definir"
  ].freeze

  # Bounding box de Costa Rica (aproximado)
  CR_LAT_MIN = 8.0
  CR_LAT_MAX = 11.5
  CR_LON_MIN = -86.0
  CR_LON_MAX = -82.0

  # Método principal que devuelve errores y recomendaciones por separado
  def address_findings(recipient_email: nil)
    errors = []
    recommendations = []

    errors << "Sin coordenadas" if missing_coordinates?
    errors << "Coordenadas cero" if latitude.to_f.zero? && longitude.to_f.zero?
    errors << "Dirección vacía" if address.blank?
    errors << "Texto de dirección inválido" if invalid_address_text?
    errors << "Fuera de Costa Rica" if out_of_cr_bounds?
    errors << "Geocodificación sin resultados" if geocode_quality == "no_match"

    # Geocodificación parcial ahora es RECOMENDACIÓN, no error
    if geocode_quality&.include?("partial")
      # Regla especial: maraya@nalakalu.com NO debe ver esto
      unless recipient_email.to_s.downcase.strip == "maraya@nalakalu.com"
        recommendations << "Geocodificación parcial: revisar dirección y confirmar ubicación en Google Maps"
      end
    end

    {errors: errors, recommendations: recommendations}
  end

  # Métodos de conveniencia
  def address_errors(recipient_email: nil)
    address_findings(recipient_email: recipient_email)[:errors]
  end

  def address_recommendations(recipient_email: nil)
    address_findings(recipient_email: recipient_email)[:recommendations]
  end

  def error_summary(recipient_email: nil)
    address_errors(recipient_email: recipient_email).join("; ")
  end

  def recommendations_summary(recipient_email: nil)
    address_recommendations(recipient_email: recipient_email).join("; ")
  end

  # Ahora has_address_errors? solo cuenta errores reales (no recomendaciones)
  def has_address_errors?(recipient_email: nil)
    address_errors(recipient_email: recipient_email).any?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[
      address description client_id created_at updated_at latitude longitude
      place_id normalized_address geocode_quality plus_code
    ]
  end

  private

  def missing_coordinates?
    latitude.blank? || longitude.blank? || latitude.zero? || longitude.zero?
  end

  def invalid_address_text?
    return true if address.blank?

    addr_lower = address.to_s.downcase.strip
    desc_lower = description.to_s.downcase.strip
    full_text = "#{addr_lower} #{desc_lower}".strip

    # 1) Detectar palabras/frases prohibidas claras
    return true if INVALID_ADDRESS_KEYWORDS.any? { |kw| full_text.include?(kw) }

    # 2) Detectar URLs (copiar enlaces en vez de direcciones)
    return true if full_text.match?(%r{https?://})

    # 3) Direcciones extremadamente cortas (ej: "x", "xx", "aaa")
    #    - Menos de 5 caracteres sin espacios
    #    - Y que no tengan números ni signos típicos de direcciones (,+#-)
    compact = addr_lower.gsub(/\s+/, "")
    if compact.length < 5 && compact !~ /[0-9]/ && compact !~ /[,+#-]/
      return true
    end

    false
  end

  def out_of_cr_bounds?
    return false if missing_coordinates?

    lat = latitude.to_f
    lon = longitude.to_f

    lat < CR_LAT_MIN || lat > CR_LAT_MAX || lon < CR_LON_MIN || lon > CR_LON_MAX
  end

  def address_is_manual_reference?
    # Si address == description, es una referencia manual, no geocodificar
    address.present? && description.present? && address.strip == description.strip
  end
end
