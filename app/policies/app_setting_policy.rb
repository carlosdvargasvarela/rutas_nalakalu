class AppSettingPolicy < ApplicationPolicy
  def show? = user.admin? || user.manager?
  def update? = user.admin? || user.manager?
end
