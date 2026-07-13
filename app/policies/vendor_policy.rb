class VendorPolicy < ApplicationPolicy
  def index?   = user.admin? || user.manager? || user.production_manager?
  def new?     = index?
  def create?  = index?
  def edit?    = user.admin? || user.manager?
  def update?  = edit?
  def destroy? = user.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
