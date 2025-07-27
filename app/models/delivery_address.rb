# app/models/delivery_address.rb
class DeliveryAddress < ApplicationRecord
  belongs_to :client

  validates :address, presence: true
end