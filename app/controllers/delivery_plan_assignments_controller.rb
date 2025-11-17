# app/controllers/delivery_plan_assignments_controller.rb
class DeliveryPlanAssignmentsController < ApplicationController
  def destroy
    assignment = DeliveryPlanAssignment.find(params[:id])
    delivery_plan = assignment.delivery_plan
    authorize delivery_plan

    # Guardar el stop_order antes de eliminar
    deleted_stop_order = assignment.stop_order

    # Eliminar sin callbacks para evitar que acts_as_list haga cosas raras
    assignment.delete
    delivery = assignment.delivery
    if delivery.present?
      delivery.delivery_items.each do |item|
        unless item.cancelled? || item.delivered?
          if item.pending?
            item.update!(status: :pending)
          elsif item.confirmed? || item.in_plan?
            item.update!(status: :confirmed)
          end
        end
      end
      delivery.update_status_based_on_items
    end

    # Recargar assignments
    delivery_plan.delivery_plan_assignments.reload

    if delivery_plan.delivery_plan_assignments.empty?
      delivery_plan.destroy
      redirect_to delivery_plans_path, notice: "El plan de ruta fue eliminado porque no tenía entregas asignadas."
    else
      # Compactar los stop_order para eliminar huecos
      compact_stop_orders(delivery_plan)

      redirect_to edit_delivery_plan_path(delivery_plan), notice: "Entrega removida del plan de ruta."
    end
  end

  private

  def compact_stop_orders(delivery_plan)
    # Obtener todos los stop_order únicos ordenados
    unique_stops = delivery_plan.delivery_plan_assignments
                                .pluck(:stop_order)
                                .uniq
                                .sort

    # Crear un mapeo de stop_order viejo => nuevo
    stop_mapping = {}
    unique_stops.each_with_index do |old_stop, index|
      stop_mapping[old_stop] = index + 1
    end

    # Actualizar todos los assignments con el nuevo stop_order
    ActiveRecord::Base.transaction do
      delivery_plan.delivery_plan_assignments.each do |assignment|
        new_stop = stop_mapping[assignment.stop_order]
        assignment.update_column(:stop_order, new_stop) if new_stop
      end
    end
  end
end
