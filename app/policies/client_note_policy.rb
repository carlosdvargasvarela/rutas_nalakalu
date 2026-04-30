# app/policies/client_note_policy.rb
class ClientNotePolicy < ApplicationPolicy
  def create?
    user.present?
  end

  def update?
    user.admin?
  end

  def destroy?
    user.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
