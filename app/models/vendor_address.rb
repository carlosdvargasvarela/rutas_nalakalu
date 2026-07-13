# app/models/vendor_address.rb
class VendorAddress < ApplicationRecord
  include Geocodable

  has_paper_trail
  belongs_to :vendor

  validate :must_have_coordinates

  def self.ransackable_attributes(_auth_object = nil)
    %w[
      address description vendor_id created_at updated_at latitude longitude
      place_id normalized_address geocode_quality
    ]
  end

  private

  def must_have_coordinates
    return if latitude.present? && longitude.present?
    errors.add(:base, "La dirección debe tener coordenadas")
  end
end
