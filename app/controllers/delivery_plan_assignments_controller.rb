# app/controllers/delivery_plan_assignments_controller.rb
class DeliveryPlanAssignmentsController < ApplicationController
  def destroy
    assignment = DeliveryPlanAssignment.find(params[:id])
    delivery_plan = assignment.delivery_plan
    assignment.destroy
    redirect_to edit_delivery_plan_path(delivery_plan), notice: "Entrega removida del plan de ruta."
  end
end