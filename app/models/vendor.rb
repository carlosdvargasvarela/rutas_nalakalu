# app/models/vendor.rb
class Vendor < ApplicationRecord
  has_paper_trail

  has_many :vendor_contacts, dependent: :destroy
  has_many :vendor_addresses, dependent: :destroy

  accepts_nested_attributes_for :vendor_contacts, allow_destroy: true, reject_if: proc { |attrs|
    attrs["name"].blank?
  }
  accepts_nested_attributes_for :vendor_addresses, allow_destroy: true, reject_if: proc { |attrs|
    attrs["address"].blank?
  }

  validates :name, presence: true
  validates :vendor_addresses, presence: {message: "debe tener al menos una dirección"}

  def self.ransackable_attributes(_auth_object = nil)
    %w[name created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[vendor_contacts vendor_addresses versions]
  end
end
