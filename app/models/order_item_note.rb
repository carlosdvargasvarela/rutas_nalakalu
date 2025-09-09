# app/models/order_item_note.rb
class OrderItemNote < ApplicationRecord
  belongs_to :order_item
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1000 }
end
