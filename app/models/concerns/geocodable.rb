# app/models/concerns/geocodable.rb
module Geocodable
  extend ActiveSupport::Concern

  included do
    validates :address, presence: true

    # Solo geocodificar si cambió la dirección Y no hay coordenadas manuales
    before_validation :geocode_enriched, if: :should_geocode?
    before_validation :refresh_zone, if: -> { will_save_change_to_latitude? || will_save_change_to_longitude? }
  end

  def full_address
    [address, description].compact.join(" - ")
  end

  def to_s
    address
  end

  # Provincia/cantón/distrito por coordenadas (sirve también para Plus Codes y
  # direcciones manuales; sin coordenadas las obtiene del texto). Vacíos si
  # Google no los trae o el punto cae fuera de Costa Rica.
  def refresh_zone
    return unless respond_to?(:province=) # VendorAddress no tiene zona

    point = [latitude, longitude].map(&:presence)
    point = Geocoder.search(build_query_for_geocode).first&.coordinates if point.any?(&:nil?)
    return if point.blank?

    # Con result_type Google a veces omite el cantón: se completa con la búsqueda sin filtrar.
    results = Geocoder.search(point.map(&:to_f), params: {components: nil, result_type: "administrative_area_level_3"})
    zone = zone_from(results)
    zone = zone_from(results + Geocoder.search(point.map(&:to_f), params: {components: nil})) if zone.compact.size < 3
    self.province, self.canton, self.district = zone
  end

  private

  def should_geocode?
    # NO geocodificar si:
    # - El address es igual a la descripción (es manual)
    # - O si el address contiene "Dirección manual"
    return false if address == description
    return false if address.to_s.include?("Dirección manual")

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

  def zone_from(results)
    comps = results.flat_map { |r| r.data["address_components"] || [] }
    return [nil, nil, nil] unless comps.any? { |c| c["types"].include?("country") && c["short_name"] == "CR" }

    [1, 2, 3].map { |lvl| comps.find { |c| c["types"].include?("administrative_area_level_#{lvl}") }&.dig("long_name") }
      .then { |prov, canton, district| [prov&.delete_prefix("Provincia de "), canton, district] }
  end
end
