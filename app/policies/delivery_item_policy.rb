# app/policies/delivery_item_policy.rb
class DeliveryItemPolicy < ApplicationPolicy
  # Bitácora de carga: solo producción, logística o admin pueden cambiar estados
  def mark_loaded?
    admin_or_manager_or_logistics?
  end

  def mark_unloaded?
    admin_or_manager_or_logistics?
  end

  def mark_missing?
    admin_or_manager_or_logistics?
  end

  def show?
    user.admin? || user.production_manager? || user.logistics?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      else
        scope.none
      end
    end
  end

  private

  def admin_or_manager_or_logistics?
    user.admin? || user.production_manager? || user.logistics?
  end
end
