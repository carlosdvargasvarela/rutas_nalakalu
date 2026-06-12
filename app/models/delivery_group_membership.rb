class DeliveryGroupMembership < ApplicationRecord
  belongs_to :delivery_group
  belongs_to :delivery

  validates :delivery_id, uniqueness: true
end
