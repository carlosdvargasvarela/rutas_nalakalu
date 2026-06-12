class DeliveryGroupPolicy < ApplicationPolicy
  def create?
    user.admin? || user.production_manager? || user.seller? || user.logistics?
  end

  alias remove_member? create?
end
