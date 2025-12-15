class DeliveryPlanPolicy < ApplicationPolicy
  # Todos pueden ver index y show (pero el scope controla qué registros ven)
  def index?
    true
  end

  def show?
    true
  end

  def update_position?
    show?
  end

  def destroy?
    # Permite a admin o logística/production manager borrar
    return false unless admin_or_manager_or_logistic?

    # Regla de negocio opcional: solo borrable si está en borrador o enviado a logística
    # (Ajusta según tus necesidades; el modelo además tiene ensure_deletable)
    record.status_draft? || record.status_sent_to_logistics? || record.status.nil?
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

  def loading?
    show?
  end

  def mark_all_loaded?
    admin_or_manager_or_logistic?
  end

  class Scope < Scope
    def resolve
      # Admin, logística y producción ven todo
      if user.admin? || user.role.to_s == "production_manager" || user.role.to_s == "logistic"
        scope.all
      else
        # Chofer ve solo sus planes
        scope.where(driver_id: user.id)
      end
    end
  end

  private

  def admin_or_manager_or_logistic?
    user.admin? || user.role.to_s == "production_manager" || user.role.to_s == "logistic"
  end
end
