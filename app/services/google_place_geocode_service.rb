# app/services/google_place_geocode_service.rb
class GooglePlaceGeocodeService
  def self.call(place_id)
    return nil if place_id.blank?

    res = Geocoder.search("place_id:#{place_id}")
    r = res.first
    return nil unless r.present?

    {
      lat: r.coordinates[0],
      lng: r.coordinates[1],
      normalized_address: r.data["formatted_address"],
      plus_code: r.data.dig("plus_code", "compound_code") || r.data.dig("plus_code", "global_code"),
      geocode_quality: [
        (r.data["partial_match"] ? "partial" : nil),
        r.data.dig("geometry", "location_type")
      ].compact.join(":")
    }
  end
end
