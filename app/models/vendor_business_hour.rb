# app/models/vendor_business_hour.rb
class VendorBusinessHour < ApplicationRecord
  has_paper_trail

  belongs_to :vendor

  DAY_NAMES = %w[Domingo Lunes Martes Miércoles Jueves Viernes Sábado].freeze

  validates :day_of_week, presence: true, inclusion: {in: 0..6}
  validates :opens_at, :closes_at, presence: true, unless: :closed?

  def day_name
    DAY_NAMES[day_of_week]
  end

  def label
    return "Cerrado" if closed? || opens_at.blank? || closes_at.blank?
    "#{opens_at.strftime("%l:%M %p").strip} - #{closes_at.strftime("%l:%M %p").strip}"
  end
end
