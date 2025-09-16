class DeliveryPlanPolicy < ApplicationPolicy
  # Todos pueden ver index y show
  def index?
    true
  end

  def show?
    true
  end

  # Solo roles especiales pueden administrar
  def create?
    admin_or_manager_or_logistic?
  end

  def new?
    create?
  end

  def update?
    admin_or_manager_or_logistic?
  end

  def edit?
    update?
  end

  def send_to_logistics?
    admin_or_manager_or_logistic?
  end

  def update_order?
    admin_or_manager_or_logistic?
  end

  def add_delivery_to_plan?
    admin_or_manager_or_logistic?
  end

  private

  def admin_or_manager_or_logistic?
    user.admin? || user.role.to_s == "production_manager" || user.role.to_s == "logistic"
  end
end