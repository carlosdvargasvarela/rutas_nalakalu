class DeliveryAddressPolicy < ApplicationPolicy
  def index?
    user.admin? || user.production_manager? || user.logistics? || user.seller? || user.driver?
  end

  def show?
    return true if user.admin? || user.production_manager? || user.logistics? || user.seller?
    if user.driver?
      return Delivery.where(delivery_address_id: record.id)
        .joins(delivery_plan_assignment: :delivery_plan)
        .where(delivery_plans: {driver_id: user.id})
        .exists?
    end
    false
  end

  def edit?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def update?
    edit?
  end

  def create?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def destroy?
    user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      elsif user.seller?
        scope.joins(client: {orders: :seller}).where(sellers: {user_id: user.id}).distinct
      elsif user.driver?
        # DeliveryAddress no tiene asociación directa a Delivery/driver, así
        # que se filtra por los delivery_address_id de las entregas
        # asignadas a un plan del driver actual.
        scope.where(id: Delivery.joins(delivery_plan_assignment: :delivery_plan)
          .where(delivery_plans: {driver_id: user.id})
          .select(:delivery_address_id))
      else
        scope.none
      end
    end
  end
end
