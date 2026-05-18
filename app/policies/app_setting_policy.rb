class AppSettingPolicy < ApplicationPolicy
  def show? = user.admin?
  def update? = user.admin?
end
