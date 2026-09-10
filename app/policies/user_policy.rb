class UserPolicy < ApplicationPolicy
  def index?
    user.admin? || user.manager?
  end

  def show?
    user.admin? || user.manager?
  end

  def edit?
    user.admin? || user.manager?
  end

  def create?
    user.admin?
  end

  def update?
    user.admin? || user.manager?
  end

  def destroy?
    user.admin?
  end

  class Scope < Scope
    def resolve
      (user.admin? || user.manager?) ? scope.all : scope.none
    end
  end
end
