# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  has_paper_trail
  belongs_to :client

  validates :address, presence: true

  def to_s
    "#{address}"
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "address", "description", "client_id", "created_at", "updated_at" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "client", "deliveries" ]
  end
end