class DeliveryGroupMembership < ApplicationRecord
  has_paper_trail

  belongs_to :delivery_group
  belongs_to :delivery

  validates :delivery_id, uniqueness: true
end
