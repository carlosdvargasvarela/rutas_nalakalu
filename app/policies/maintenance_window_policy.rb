# app/policies/maintenance_window_policy.rb
class MaintenanceWindowPolicy < ApplicationPolicy
  def show? = user.admin? || user.manager?
  def new? = user.admin? || user.manager?
  def create? = user.admin? || user.manager?
  def deactivate? = user.admin? || user.manager?
end
