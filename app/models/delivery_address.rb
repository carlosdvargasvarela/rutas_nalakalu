# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  # has_paper_trail
  belongs_to :client

  validates :address, presence: true

  # Solo geocodificar si cambió la dirección Y no hay coordenadas manuales
  before_validation :geocode_enriched, if: :should_geocode?

  def full_address
    [ address, description ].compact.join(" - ")
  end

  def to_s
    address
  end

  private

  def should_geocode?
    # Solo geocodificar si:
    # 1. La dirección cambió
    # 2. Y NO hay coordenadas manuales (o las coordenadas también cambiaron)
    will_save_change_to_address? && !has_manual_coordinates?
  end

  def has_manual_coordinates?
    # Si hay coordenadas Y cambiaron, significa que son manuales
    (latitude.present? && longitude.present?) &&
    (will_save_change_to_latitude? || will_save_change_to_longitude?)
  end

  def build_query_for_geocode
    base = address.to_s.strip
    desc = description.to_s.strip
    parts = [ base, desc ].reject(&:blank?)
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
      self.geocode_quality = [ partial, loc_type ].compact.join(":")

    else
      # Sin match: marca calidad; no sobrescribas coords existentes
      self.geocode_quality = "no_match"
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[
      address description client_id created_at updated_at latitude longitude
      place_id normalized_address geocode_quality plus_code
    ]
  end
end
