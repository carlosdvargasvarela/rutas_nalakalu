class NotificationPolicy < ApplicationPolicy
  def index?
    true
  end

  def mark_as_read?
    record.user_id == user.id
  end

  def mark_all_as_read?
    true
  end

  def mark_group_as_read?
    true
  end

  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
