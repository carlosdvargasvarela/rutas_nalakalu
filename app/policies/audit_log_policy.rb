class AuditLogPolicy < ApplicationPolicy
  def index?
    user.present? && (user.admin? || user.manager? || user.role.in?(%w[logistics production_manager]))
  end

  class Scope < Scope
    def resolve
      scope # global log; si necesitas filtrar por rol, ajustar aquí
    end
  end
end
