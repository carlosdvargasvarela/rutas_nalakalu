# app/models/order_item_note.rb
class OrderItemNote < ApplicationRecord
  belongs_to :order_item
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1000 }

  def self.ransackable_attributes(auth_object = nil)
    [ "body", "closed", "created_at", "id", "order_item_id", "updated_at", "user_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "order_item", "user" ]
  end
end
