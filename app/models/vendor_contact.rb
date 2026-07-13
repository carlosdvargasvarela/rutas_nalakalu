# app/models/vendor_contact.rb
class VendorContact < ApplicationRecord
  has_paper_trail

  belongs_to :vendor

  validates :name, presence: true

  scope :primary_first, -> { order(is_primary: :desc, created_at: :asc) }

  before_save :ensure_single_primary

  private

  def ensure_single_primary
    return unless is_primary?
    vendor.vendor_contacts.where.not(id: id).update_all(is_primary: false)
  end
end
