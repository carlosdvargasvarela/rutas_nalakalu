# app/models/seller.rb
class Seller < ApplicationRecord
  has_paper_trail
  belongs_to :user
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :seller_code, presence: true, uniqueness: true
end