# app/policies/delivery_policy.rb

class DeliveryPolicy < ApplicationPolicy
  # =============================================================================
  # PERMISOS BÁSICOS (CRUD)
  # =============================================================================

  def index?
    user.admin? || user.production_manager? || user.logistics? || user.seller? || user.driver?
  end

  def show?
    return true if user.admin? || user.production_manager? || user.logistics? || user.seller?
    return true if user.driver? && record.delivery_plan&.driver_id == user.id
    false
  end

  def edit?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def update?
    edit?
  end

  def create?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def destroy?
    user.admin?
  end

  # =============================================================================
  # PERMISOS DE GESTIÓN OPERATIVA (PRODUCTION)
  # =============================================================================

  def management?
    user.admin? || user.production_manager? || user.logistics?
  end

  def approve?
    user.admin? || user.logistics? || user.production_manager?
  end

  def quick_update?
    user.admin? || user.production_manager? || user.logistics?
  end

  def add_product?
    user.admin? || user.production_manager? || user.logistics?
  end

  # =============================================================================
  # PERMISOS DE CARGA (LOADING)
  # =============================================================================

  def mark_all_loaded?
    user.admin? || user.production_manager? || user.logistics?
  end

  def reset_load_status?
    user.admin? || user.production_manager? || user.logistics?
  end

  # =============================================================================
  # PERMISOS DE CASOS ESPECIALES
  # =============================================================================

  def new_internal_delivery?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def create_internal_delivery?
    new_internal_delivery?
  end

  def new_service_case?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def create_service_case?
    new_service_case?
  end

  def new_service_case_for_existing?
    new_service_case?
  end

  def create_service_case_for_existing?
    new_service_case?
  end

  # =============================================================================
  # PERMISOS DE REASIGNACIÓN
  # =============================================================================

  def reassign_seller?
    user.admin? || user.logistics? || user.production_manager?
  end

  def take_order?
    user.seller?
  end

  # =============================================================================
  # PERMISOS DE CONSULTA
  # =============================================================================

  def addresses_for_client?
    index?
  end

  def orders_for_client?
    index?
  end

  # =============================================================================
  # SCOPE - FILTRADO POR ROL
  # =============================================================================

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        # Acceso completo a todas las entregas
        scope.all
      elsif user.seller?
        # Solo entregas de pedidos asignados al vendedor
        scope.joins(order: :seller).where(sellers: {user_id: user.id})
      elsif user.driver?
        # Solo entregas asignadas a planes donde el driver es el usuario actual
        scope.joins(delivery_plan_assignments: {delivery_plan: :driver})
          .where(delivery_plans: {driver_id: user.id})
      else
        scope.none
      end
    end
  end
end
