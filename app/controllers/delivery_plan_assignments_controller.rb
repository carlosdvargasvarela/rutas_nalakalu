# app/controllers/delivery_plan_assignments_controller.rb
class DeliveryPlanAssignmentsController < ApplicationController
  def destroy
    assignment = DeliveryPlanAssignment.find(params[:id])
    delivery_plan = assignment.delivery_plan
    assignment.destroy

    if delivery_plan.delivery_plan_assignments.reload.empty?
      delivery_plan.destroy
      redirect_to delivery_plans_path, notice: "El plan de ruta fue eliminado porque no tenía entregas asignadas."
    else
      redirect_to edit_delivery_plan_path(delivery_plan), notice: "Entrega removida del plan de ruta."
    end
  end
end