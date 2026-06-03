class ShowroomPolicy < ApplicationPolicy
  def index?   = user.admin? || user.manager?
  def new?     = user.admin? || user.manager?
  def create?  = new?
  def edit?    = user.admin? || user.manager?
  def update?  = edit?
  def destroy? = user.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
