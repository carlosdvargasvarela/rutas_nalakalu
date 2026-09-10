class DeliveryImportPolicy < ApplicationPolicy
  # Todos pueden ver index y show (pero el scope controla qué registros ven)
  def index?
    true
  end

  def show?
    true
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

  def update_rows?
    update?
  end

  def edit?
    update?
  end

  def process_import?
    show?
  end

  def template?
    create?
  end

  class Scope < Scope
    def resolve
      if admin_or_manager_or_logistic?(user)
        scope.all
      else
        # Cada usuario ve solo las importaciones que él mismo subió
        scope.where(user_id: user.id)
      end
    end

    private

    def admin_or_manager_or_logistic?(user)
      user.admin? || user.production_manager? || user.logistics?
    end
  end

  private

  def admin_or_manager_or_logistic?
    user.admin? || user.production_manager? || user.logistics?
  end
end
