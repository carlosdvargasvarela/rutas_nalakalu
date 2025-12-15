# app/policies/order_item_policy.rb
class OrderItemPolicy < ApplicationPolicy
  def confirm?
    user.admin? || user.production_manager?
  end

  def unconfirm?
    user.admin? || user.production_manager?
  end
end
