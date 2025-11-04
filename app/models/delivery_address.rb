# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  has_paper_trail
  belongs_to :client

  validates :address, presence: true

  # Hacemos una única geocodificación enriquecida cuando cambia la dirección
  before_validation :geocode_enriched, if: :will_save_change_to_address?

  def full_address
    [ address, description ].compact.join(" - ")
  end

  def to_s
    address
  end

  private

  # Mejora el query combinando address + description para dar más contexto al geocoder
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

      # Coordenadas
      if (loc = r.coordinates).present?
        self.latitude, self.longitude = loc
      end

      # place_id (para fijar el lugar a futuro)
      self.place_id = r.data["place_id"] if r.data["place_id"].present?

      # Plus code desde la misma respuesta (sin segunda llamada)
      if (pc = r.data["plus_code"]).present?
        self.plus_code = pc["compound_code"] || pc["global_code"]
      else
        # Limpia si la nueva geocodificación no trae plus_code
        self.plus_code = nil
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
