# app/models/vendor_contact.rb
class VendorContact < ApplicationRecord
  has_paper_trail

  belongs_to :vendor

  include HasPrimaryContact
end
