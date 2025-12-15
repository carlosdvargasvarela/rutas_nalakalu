# app/models/client.rb
class Client < ApplicationRecord
  has_paper_trail
  has_many :delivery_addresses, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["name", "phone", "email", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["delivery_addresses", "orders", "versions"]
  end
end
