# app/policies/seller_policy.rb
class SellerPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      user.sees_admin_views? ? scope.all : scope.none
    end
  end

  def index?
    user.sees_admin_views?
  end

  def show?
    user.sees_admin_views?
  end
end
