# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  def index?
    user.admin? || user.production_manager? || user.logistics? || user.seller?
  end

  def show?
    user.admin? || user.production_manager? || user.logistics? || user.seller? || user.driver?
  end

  def edit?
    user.admin? || user.production_manager?
  end

  def create?
    user.admin? || user.seller? || user.production_manager?
  end

  def update?
    user.admin? || user.production_manager?
  end

  def destroy?
    user.admin?
  end

  def confirm_all_items_ready?
    user.production_manager? || user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      elsif user.seller?
        scope.joins(:seller).where(sellers: {user_id: user.id})
      elsif user.driver?
        # Solo pedidos con alguna entrega asignada a un plan del driver actual
        scope.joins(deliveries: {delivery_plan_assignment: :delivery_plan})
          .where(delivery_plans: {driver_id: user.id})
          .distinct
      else
        scope.none
      end
    end
  end
end
