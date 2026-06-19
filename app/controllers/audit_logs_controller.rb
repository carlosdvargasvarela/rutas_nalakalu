# app/controllers/audit_logs_controller.rb
class AuditLogsController < ApplicationController
  helper :audit_logs
  helper :delivery_events
  helper :timeline

  before_action :authenticate_user!
  after_action :verify_authorized

  # ── INDEX ──────────────────────────────────────────────────────────────────

  def index
    authorize :audit_log, :index?

    @active_tab = params[:tab].presence_in(%w[events versions]) || "events"

    # Eventos de negocio
    events_scope = DeliveryEvent.includes(:actor, :delivery).recent

    events_scope = events_scope.where(delivery_id: params[:delivery_id]) if params[:delivery_id].present?
    events_scope = events_scope.for_action(params[:event_action]) if params[:event_action].present?
    events_scope = events_scope.by_actor(params[:event_actor_id]) if params[:event_actor_id].present?

    if params[:event_from].present?
      events_scope = events_scope.where("created_at >= ?", params[:event_from].to_date.beginning_of_day)
    end
    if params[:event_to].present?
      events_scope = events_scope.where("created_at <= ?", params[:event_to].to_date.end_of_day)
    end

    @delivery_events = events_scope.page(params[:page]).per(50)
    @total_events = DeliveryEvent.count

    # Cambios técnicos
    @q = PaperTrail::Version.ransack(params[:q])
    @q.sorts = "created_at desc" if @q.sorts.empty?

    @versions = @q.result.page(params[:page]).per(50)
    user_ids = @versions.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }
    @items_cache = preload_items(@versions)
    @item_types = PaperTrail::Version.distinct.pluck(:item_type).compact.sort
  end

  # ── RESOURCE HISTORY ──────────────────────────────────────────────────────

  def resource_history
    authorize :audit_log, :index?

    @item_type = params[:item_type]
    @item_id = params[:item_id]

    @resource = @item_type.constantize.find_by(id: @item_id)

    # PaperTrail — sin límite de paginación aquí para el merge
    versions_scope = PaperTrail::Version
      .where(item_type: @item_type, item_id: @item_id)
      .order(created_at: :desc)
      .limit(200)

    @events_count = PaperTrail::Version
      .where(item_type: @item_type, item_id: @item_id)
      .group(:event)
      .count

    delivery_events_scope = delivery_events_for(@resource)
    plan_events_scope = plan_events_for(@resource)

    # ── Construir timeline unificado ────────────────────────────────────────
    entries = []

    delivery_events_scope.each do |e|
      entries << TimelineEntry.new(timestamp: e.created_at, source: :delivery_event, record: e)
    end

    plan_events_scope.each do |e|
      entries << TimelineEntry.new(timestamp: e.created_at, source: :plan_event, record: e)
    end

    versions_scope.each do |v|
      entries << TimelineEntry.new(timestamp: v.created_at, source: :paper_trail, record: v)
    end

    # El agrupador devuelve array de { primary:, secondary: }
    @timeline_groups = TimelineGrouper.group(entries)

    # Usuarios para PaperTrail
    user_ids = versions_scope.pluck(:whodunnit).compact.uniq
    @users_by_id = User.where(id: user_ids).index_by { |u| u.id.to_s }

    # Registros relacionados
    @related_versions = related_versions_for(@resource)

    if @related_versions.present?
      related_user_ids = @related_versions.pluck(:whodunnit).compact.uniq
      @users_by_id.merge!(User.where(id: related_user_ids).index_by { |u| u.id.to_s })
    end
  end

  private

  # ── Helpers privados ───────────────────────────────────────────────────────

  # DeliveryEvent propios del recurso, o (si es un DeliveryPlan) los de todas sus entregas.
  def delivery_events_for(resource)
    case resource
    when Delivery
      resource.delivery_events.includes(:actor).recent
    when DeliveryPlan
      DeliveryEvent.where(delivery_id: resource.deliveries.select(:id)).includes(:actor).recent
    else
      DeliveryEvent.none
    end
  end

  # PlanEvent propios del recurso, o (si es una Delivery) los de su plan actual.
  # Nota: Delivery usa has_one :delivery_plan_assignment, así que solo se ve el
  # plan vigente, no el historial de planes pasados (esa relación no se conserva).
  def plan_events_for(resource)
    case resource
    when DeliveryPlan
      resource.plan_events.includes(:actor).recent
    when Delivery
      plan = resource.delivery_plan_assignment&.delivery_plan
      plan ? plan.plan_events.includes(:actor).recent : PlanEvent.none
    else
      PlanEvent.none
    end
  end

  def preload_items(versions)
    versions.group_by(&:item_type).each_with_object({}) do |(type, type_versions), cache|
      ids = type_versions.map(&:item_id).uniq.compact
      cache[type] = type.constantize.where(id: ids).index_by(&:id)
    rescue NameError, StandardError => e
      Rails.logger.warn "preload_items error para #{type}: #{e.message}"
      cache[type] = {}
    end
  end

  def related_versions_for(resource)
    return PaperTrail::Version.none if resource.blank?

    case resource
    when Delivery then related_for_delivery(resource)
    when Order then related_for_order(resource)
    when DeliveryPlan then related_for_plan(resource)
    else PaperTrail::Version.none
    end
  end

  def related_for_delivery(delivery)
    item_ids = delivery.delivery_items.pluck(:id)
    return PaperTrail::Version.none if item_ids.empty?

    PaperTrail::Version
      .where(item_type: "DeliveryItem", item_id: item_ids)
      .order(created_at: :desc)
      .limit(50)
  end

  def related_for_order(order)
    order_item_ids = order.order_items.pluck(:id)
    delivery_ids = order.deliveries.pluck(:id)

    conditions = []
    conditions << {item_type: "OrderItem", item_id: order_item_ids} if order_item_ids.any?
    conditions << {item_type: "Delivery", item_id: delivery_ids} if delivery_ids.any?
    return PaperTrail::Version.none if conditions.empty?

    query = PaperTrail::Version.where(conditions.shift)
    conditions.each { |c| query = query.or(PaperTrail::Version.where(c)) }
    query.order(created_at: :desc).limit(50)
  end

  def related_for_plan(plan)
    ids = plan.delivery_plan_assignments.pluck(:id)
    return PaperTrail::Version.none if ids.empty?

    PaperTrail::Version
      .where(item_type: "DeliveryPlanAssignment", item_id: ids)
      .order(created_at: :desc)
      .limit(50)
  end
end
