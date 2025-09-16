# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  after_create :change_deliveries_statuses
  before_destroy :revert_statuses

  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order

  private

  def change_deliveries_statuses
    unless delivery_plan.draft? && delivery.scheduled?
      delivery.delivery_items.update_all(status: DeliveryItem.statuses[:in_plan])
      delivery.update_columns(status: Delivery.statuses[:in_plan])
    end
  end

  def revert_statuses
    delivery.delivery_items.find_each do |item|
      new_status = item.confirmed? ? :confirmed : :pending
      item.update_columns(status: DeliveryItem.statuses[new_status])
    end

    if delivery.delivery_items.where.not(status: DeliveryItem.statuses[:pending]).exists?
      delivery.update_columns(status: Delivery.statuses[:ready_to_deliver])
    else
      delivery.update_columns(status: Delivery.statuses[:scheduled])
    end
  end
end
