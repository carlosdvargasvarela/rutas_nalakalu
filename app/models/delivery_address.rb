# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  has_paper_trail
  belongs_to :client

  validates :address, presence: true

  # Solo geocodificar si cambió la dirección Y no hay coordenadas manuales
  before_validation :geocode_enriched, if: :should_geocode?

  def full_address
    [address, description].compact.join(" - ")
  end

  def to_s
    address
  end

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

  def address_errors
    errors = []
    errors << "Sin coordenadas" if missing_coordinates?
    errors << "Coordenadas cero" if latitude.to_f.zero? && longitude.to_f.zero?
    errors << "Dirección vacía" if address.blank?
    errors << "Texto de dirección inválido" if invalid_address_text?
    errors << "Fuera de Costa Rica" if out_of_cr_bounds?
    errors << "Geocodificación sin resultados" if geocode_quality == "no_match"
    errors << "Geocodificación parcial" if geocode_quality&.include?("partial")
    errors
  end

  def has_address_errors?
    address_errors.any?
  end

  def error_summary
    address_errors.join("; ")
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

  def should_geocode?
    # Solo geocodificar si:
    # 1. La dirección cambió
    # 2. Y NO hay coordenadas manuales (o las coordenadas también cambiaron)
    will_save_change_to_address? && !has_manual_coordinates?
  end

  def has_manual_coordinates?
    # Si hay coordenadas Y cambiaron, significa que son manuales
    latitude.present? && longitude.present? &&
      (will_save_change_to_latitude? || will_save_change_to_longitude?)
  end

  def build_query_for_geocode
    base = address.to_s.strip
    desc = description.to_s.strip
    parts = [base, desc].reject(&:blank?)
    parts.join(", ")
  end

  def geocode_enriched
    query = build_query_for_geocode

    # Usa la configuración global del initializer (Google, es, region cr, components country:CR)
    results = Geocoder.search(query)

    if results.present?
      r = results.first

      # Solo actualizar coordenadas si NO fueron ingresadas manualmente
      if latitude.blank? || longitude.blank?
        if (loc = r.coordinates).present?
          self.latitude, self.longitude = loc
        end
      end

      # place_id (para fijar el lugar a futuro)
      self.place_id = r.data["place_id"] if r.data["place_id"].present?

      # Plus code desde la misma respuesta (sin segunda llamada)
      # Solo actualizar si no hay plus_code manual
      if plus_code.blank?
        if (pc = r.data["plus_code"]).present?
          self.plus_code = pc["compound_code"] || pc["global_code"]
        end
      end

      # Dirección normalizada (útil para mostrar/auditar)
      self.normalized_address = r.data["formatted_address"] || r.address

      # Calidad: parcial y tipo de localización (ROOFTOP, APPROXIMATE, etc.)
      partial = r.data["partial_match"] ? "partial" : nil
      loc_type = r.data.dig("geometry", "location_type")
      self.geocode_quality = [partial, loc_type].compact.join(":")

    else
      # Sin match: marca calidad; no sobrescribas coords existentes
      self.geocode_quality = "no_match"
    end
  end
end
