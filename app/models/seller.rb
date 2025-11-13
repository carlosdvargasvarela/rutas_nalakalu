# app/models/seller.rb
class Seller < ApplicationRecord
  # has_paper_trail # Temporalmente desactivado por bug en v16.0
  belongs_to :user
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :seller_code, presence: true, uniqueness: true

  # Ransack (para filtros)
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "name", "seller_code", "updated_at", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["orders", "user", "versions"]
  end

end