# app/policies/order_contact_policy.rb
class OrderContactPolicy < ApplicationPolicy
  def create?
    user.admin? || user.production_manager? || user.seller?
  end

  def update?
    user.admin? || user.production_manager? || user.seller?
  end

  def destroy?
    user.admin? || user.production_manager? || user.seller?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
