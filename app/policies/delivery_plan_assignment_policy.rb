# app/policies/delivery_plan_assignment_policy.rb
class DeliveryPlanAssignmentPolicy < ApplicationPolicy
  # Solo admin, production_manager o logistic pueden eliminar assignments;
  # si la entrega está cancelada o reagendada, solo un admin puede quitar
  # esa parada de la ruta (las demás siguen la regla de siempre).
  def destroy?
    delivery = record.respond_to?(:delivery) ? record.delivery : nil
    return admin_or_manager_or_logistic? unless delivery&.cancelled? || delivery&.rescheduled?

    user.admin?
  end

  private

  def admin_or_manager_or_logistic?
    user.admin? || user.production_manager? || user.logistics?
  end
end
