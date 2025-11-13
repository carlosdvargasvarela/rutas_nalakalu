# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  # has_paper_trail
  belongs_to :client

  validates :address, presence: true

  geocoded_by :address,
              latitude: :latitude,
              longitude: :longitude

  after_validation :geocode_and_set_plus_code, if: :will_save_change_to_address?

  def full_address
    [ address, description ].compact.join(" - ")
  end

  private

  def geocode_and_set_plus_code
    if (coords = Geocoder.coordinates(address))
      self.latitude, self.longitude = coords
      # segunda llamada a la API con detalles (para obtener plus_code)
      results = Geocoder.search(address, lookup: :google, params: { result_type: "plus_code" })
      if results.present? && results.first.data["plus_code"]
        self.plus_code = results.first.data["plus_code"]["compound_code"]
      end
    end
  end
  def to_s
    address
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "address", "description", "client_id", "created_at", "updated_at", "latitude", "longitude" ]
  end
end
