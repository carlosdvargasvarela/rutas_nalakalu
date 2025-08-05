# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  def index?
    user.admin? || user.production_manager? || user.logistics? || user.seller?
  end

  def show?
    user.admin? || user.production_manager? || user.logistics? ||
      (user.seller? && record.seller.user_id == user.id)
  end

  def create?
    user.admin? || user.seller? || user.production_manager?
  end

  def update?
    user.admin? || user.production_manager? # || (user.seller? && record.seller.user_id == user.id)
  end

  def destroy?
    user.admin?
  end

  def confirm_all_items_ready?
    user.production_manager? || user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      elsif user.seller?
        scope.joins(:seller).where(sellers: { user_id: user.id })
      else
        scope.none
      end
    end
  end
end
