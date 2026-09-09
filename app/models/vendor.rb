# app/models/vendor.rb
class Vendor < ApplicationRecord
  has_paper_trail

  has_many :vendor_contacts, dependent: :destroy
  has_many :vendor_addresses, dependent: :destroy
  has_many :vendor_business_hours, dependent: :destroy

  accepts_nested_attributes_for :vendor_contacts, allow_destroy: true, reject_if: proc { |attrs|
    attrs["name"].blank?
  }
  accepts_nested_attributes_for :vendor_addresses, allow_destroy: true, reject_if: proc { |attrs|
    attrs["address"].blank?
  }
  accepts_nested_attributes_for :vendor_business_hours

  validates :name, presence: true
  validates :vendor_addresses, presence: {message: "debe tener al menos una dirección"}

  def self.ransackable_attributes(_auth_object = nil)
    %w[name created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[vendor_contacts vendor_addresses vendor_business_hours versions]
  end

  # Lun..Dom, en el orden en que se muestran en admin y al conductor.
  DISPLAY_DAY_ORDER = [1, 2, 3, 4, 5, 6, 0].freeze

  def business_hours_by_day
    vendor_business_hours.index_by(&:day_of_week)
  end

  def hours_for(day_of_week)
    business_hours_by_day[day_of_week]
  end

  def today_hours
    hours_for(Date.current.wday)
  end
end
