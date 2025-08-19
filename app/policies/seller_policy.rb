# app/policies/seller_policy.rb
class SellerPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      user.admin? ? scope.all : scope.none
    end
  end

  def index?
    user.admin?
  end

  def show?
    user.admin?
  end
end