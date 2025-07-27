# app/models/client.rb
class Client < ApplicationRecord
  has_many :delivery_addresses, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true
end