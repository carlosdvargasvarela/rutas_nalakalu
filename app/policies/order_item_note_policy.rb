class OrderItemNotePolicy < ApplicationPolicy
  # Todos pueden VER notas (aunque no tenemos index/show, podemos usar scope)
  def new?
    create?
  end

  def create?
    user.production_manager? || user.admin?
  end

  def edit?
    update?
  end

  def update?
    (user.production_manager? && record.user == user) || user.admin?
  end

  def destroy?
    update? # mismas reglas que editar
  end

  def close?
    update?
  end

  def reopen?
    update?
  end

  class Scope < Scope
    def resolve
      scope.all # todos pueden leer notas
    end
  end
end
