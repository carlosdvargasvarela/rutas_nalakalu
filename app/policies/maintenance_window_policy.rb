# app/policies/maintenance_window_policy.rb
class MaintenanceWindowPolicy < ApplicationPolicy
  def show? = user.admin?
  def new? = user.admin?
  def create? = user.admin?
  def deactivate? = user.admin?
end
