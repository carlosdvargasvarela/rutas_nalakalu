# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  belongs_to :delivery_plan
  belongs_to :delivery

  # Validación opcional
  validates :stop_order, numericality: { only_integer: true, allow_nil: true }
end