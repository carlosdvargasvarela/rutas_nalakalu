# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  # Validación opcional
  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order
end