# app/models/seller.rb
class Seller < ApplicationRecord
  has_paper_trail
  belongs_to :user
  # Los pedidos en stand-by de QuickBooks no se usan hasta liberarlos (ver Admin::QuickbooksController#release).
  has_many :orders, -> { where(qb_standby: false) }, dependent: :destroy
  has_many :standby_orders, -> { where(qb_standby: true) }, class_name: "Order", dependent: :destroy

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
