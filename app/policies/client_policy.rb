# app/policies/client_policy.rb
class ClientPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin? || user.seller?
        scope.all
      else
        scope.none
      end
    end
  end

  def index?
    user.admin? || user.seller?
  end

  def show?
    user.admin? || user.seller?
  end

  def create?
    user.admin? || user.seller?
  end

  def update?
    user.admin? || user.seller?
  end

  def destroy?
    return false unless user.admin? || user.seller?
    record.orders.none? && record.delivery_addresses.none?
  end
end
