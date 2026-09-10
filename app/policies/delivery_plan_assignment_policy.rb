# app/policies/delivery_plan_assignment_policy.rb
class DeliveryPlanAssignmentPolicy < ApplicationPolicy
  # Solo admin, production_manager o logistic pueden eliminar assignments
  def destroy?
    admin_or_manager_or_logistic?
  end

  private

  def admin_or_manager_or_logistic?
    user.admin? || user.production_manager? || user.logistics?
  end
end
