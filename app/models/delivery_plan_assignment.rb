# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  belongs_to :delivery
  belongs_to :delivery_plan
end