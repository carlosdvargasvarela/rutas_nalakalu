# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  after_create :change_deliveries_statuses
  before_destroy :revert_statuses

  # Validación opcional
  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order

  private

  def change_deliveries_statuses
    delivery.delivery_items.each do |item|
      item.update!(status: "in_plan")
    end
    delivery.update!(status: "in_plan")
  end

  def revert_statuses
    delivery.delivery_items.each do |item|
      item.update!(status: "ready_to_deliver")
    end
    delivery.update!(status: "confirmed")
  end
end
