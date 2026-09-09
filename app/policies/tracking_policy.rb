class TrackingPolicy < ApplicationPolicy
  def index?
    !user.driver?
  end
end
