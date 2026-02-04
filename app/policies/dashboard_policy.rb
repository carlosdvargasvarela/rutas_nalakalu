# /app/policies/dashboard_policy.rb
class DashboardPolicy < ApplicationPolicy
  def index?
    true
  end
end
