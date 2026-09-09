class VendorContactPolicy < ApplicationPolicy
  def create? = user.admin? || user.manager?
  def update? = create?
  def destroy? = create?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
