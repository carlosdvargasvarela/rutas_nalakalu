class DeliveryItemNote < ApplicationRecord
  has_paper_trail

  belongs_to :delivery_item
  belongs_to :user

  validates :body, presence: true, length: {maximum: 1000}

  scope :open, -> { where.not(closed: true) }

  def self.ransackable_attributes(auth_object = nil)
    ["body", "closed", "created_at", "id", "delivery_item_id", "updated_at", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["delivery_item", "user"]
  end
end
