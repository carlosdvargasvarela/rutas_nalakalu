# app/controllers/audit_logs_controller.rb
class AuditLogsController < ApplicationController
  helper :audit_logs
  before_action :authenticate_user!
  before_action :authorize_audit_access # Solo admin/producción

  def index
    @q = PaperTrail::Version.ransack(params[:q])
    @q.sorts = "created_at desc" if @q.sorts.empty?

    @versions = @q.result
      .page(params[:page])
      .per(50)

    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    @items_cache = preload_items(@versions)

    @item_types = PaperTrail::Version.distinct.pluck(:item_type).compact.sort
    @events = PaperTrail::Version.distinct.pluck(:event).compact

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def resource_history
    @item_type = params[:item_type]
    @item_id = params[:item_id]

    base_scope = PaperTrail::Version.where(item_type: @item_type, item_id: @item_id)

    @events_count = base_scope.group(:event).count

    @versions = base_scope
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @resource = @item_type.constantize.find_by(id: @item_id)

    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    @items_cache = preload_items(@versions)

    # versiones relacionadas (Delivery, Order, DeliveryPlan)
    @related_versions = related_versions_for(@resource)

    # Usuarios también de versiones relacionadas
    if @related_versions.present?
      related_user_ids = @related_versions.pluck(:whodunnit).compact.uniq
      related_users = User.where(id: related_user_ids).index_by { |u| u.id.to_s }
      @users_by_id.merge!(related_users)
    end
  end

  def compare
    @version_from = PaperTrail::Version.find(params[:from_id])
    @version_to = PaperTrail::Version.find(params[:to_id])

    @diff = calculate_diff(@version_from, @version_to)
  end

  private

  def authorize_audit_access
    unless current_user.admin? || current_user.production?
      redirect_to root_path, alert: "No tienes permisos para ver el log de auditoría"
    end
  end

  # ==================== DIFF ENTRE VERSIONES ======================

  def calculate_diff(version_from, version_to)
    from_state = state_after_version(version_from)
    to_state = state_after_version(version_to)

    all_keys = (from_state.keys + to_state.keys).uniq

    all_keys.each_with_object({}) do |key, diff|
      val_from = from_state[key]
      val_to = to_state[key]
      diff[key] = {from: val_from, to: val_to} if val_from != val_to
    end
  end

  # Estado "después de este cambio" (histórico real)
  def state_after_version(version)
    return {} if version.event == "destroy"

    next_version = version.next

    obj =
      if next_version
        # Estado justo antes del siguiente cambio = después de este
        next_version.reify
      else
        # Esta es la última versión → usamos el modelo vivo
        version.item
      end

    obj&.attributes || {}
  end

  # ==================== PRECARGA DE ITEMS =========================

  def preload_items(versions)
    items_cache = {}
    versions_by_type = versions.group_by(&:item_type)

    versions_by_type.each do |type, type_versions|
      ids = type_versions.map(&:item_id).uniq.compact
      items_cache[type] = type.constantize.where(id: ids).index_by(&:id)
    rescue NameError => e
      Rails.logger.warn "No se pudo cargar el modelo #{type}: #{e.message}"
      items_cache[type] = {}
    rescue => e
      Rails.logger.error "Error al precargar items de #{type}: #{e.message}"
      items_cache[type] = {}
    end

    items_cache
  end

  # ==================== VERSIONES RELACIONADAS ====================

  def related_versions_for(resource)
    return PaperTrail::Version.none if resource.blank?

    case resource
    when Delivery
      related_versions_for_delivery(resource)
    when Order
      related_versions_for_order(resource)
    when DeliveryPlan
      related_versions_for_delivery_plan(resource)
    else
      PaperTrail::Version.none
    end
  end

  # Cambios en DeliveryItem de esta entrega
  def related_versions_for_delivery(delivery)
    item_ids = delivery.delivery_items.pluck(:id)
    return PaperTrail::Version.none if item_ids.empty?

    PaperTrail::Version
      .where(item_type: "DeliveryItem", item_id: item_ids)
      .order(created_at: :desc)
      .limit(50)
  end

  # Cambios en OrderItem y Delivery de este pedido
  def related_versions_for_order(order)
    order_item_ids = order.order_items.pluck(:id)
    delivery_ids = order.deliveries.pluck(:id)

    conditions = []
    conditions << {item_type: "OrderItem", item_id: order_item_ids} if order_item_ids.any?
    conditions << {item_type: "Delivery", item_id: delivery_ids} if delivery_ids.any?

    return PaperTrail::Version.none if conditions.empty?

    query = PaperTrail::Version.where(conditions.shift)
    conditions.each { |cond| query = query.or(PaperTrail::Version.where(cond)) }

    query.order(created_at: :desc).limit(50)
  end

  # Cambios en DeliveryPlanAssignment de este plan
  def related_versions_for_delivery_plan(plan)
    assignment_ids = plan.delivery_plan_assignments.pluck(:id)
    return PaperTrail::Version.none if assignment_ids.empty?

    PaperTrail::Version
      .where(item_type: "DeliveryPlanAssignment", item_id: assignment_ids)
      .order(created_at: :desc)
      .limit(50)
  end
end
