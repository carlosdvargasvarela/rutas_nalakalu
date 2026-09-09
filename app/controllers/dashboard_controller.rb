# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :dashboard, :index?

    if current_user&.role.to_s == "driver"
      redirect_to driver_delivery_plans_path and return
    end

    # Rango de fechas: Desde hoy hasta el final de la próxima semana
    @error_date_range = Date.current..Date.current.next_week.end_of_week

    @today_stats = build_today_stats
    @active_orders_count = current_user_orders.where(status: [:pending, :in_production]).count
    @unread_notifications_count = current_user.notifications.unread.count

    # Entregas de esta semana sin plan
    @unplanned_this_week = current_user_deliveries
      .where(delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
      .available_for_plan
      .includes(order: [:client, :seller], delivery_address: :client)
      .order(:delivery_date)
      .page(params[:page_unplanned])
      .per(10)

    # Cola unificada: errores, servicio, reparación, sala, aprobación,
    # bodegaje por vencer y reprogramaciones — una sola tabla en vez de una
    # pestaña por categoría, filtrable por categoría vía ?category=
    attention_items = build_attention_queue
    attention_items = attention_items.select { |i| i[:categories].include?(params[:category].to_sym) } if params[:category].present?
    @attention_queue = Kaminari.paginate_array(attention_items).page(params[:page_attention]).per(15)

    @data_quality_issues = current_user.admin? ? build_data_quality_issues : []

    @pending_tasks = build_pending_tasks
    @recent_notifications = current_user.notifications.recent.limit(5)
  end

  private

  def redirect_by_role
    if current_user.production_manager?
      redirect_to management_production_deliveries_path and return
    elsif current_user.driver?
      redirect_to driver_delivery_plans_path and return
    elsif current_user.logistics?
      redirect_to delivery_plans_path and return
    end
    # Si es seller o admin, continúa al dashboard normal
  end

  def build_today_stats
    today_deliveries = current_user_deliveries.where(delivery_date: Date.current)

    {
      trucks_in_route: DeliveryPlan.status_in_progress.with_deliveries_on(Date.current).count,
      total_today: today_deliveries.count,
      completed_today: today_deliveries.where(status: :delivered).count
    }
  end

  # Recorre una sola vez las entregas candidatas y les asigna todas las
  # categorías que apliquen (una entrega puede tener varias a la vez), en vez
  # de hacer un query + scan separado por categoría.
  def build_attention_queue
    candidates = current_user_deliveries
      .where(delivery_date: @error_date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .includes(
        order: [:client, :seller, :order_items],
        delivery_address: :client,
        delivery_items: :order_item
      )

    items_by_id = {}
    can_see_approvals = current_user.admin? || current_user.production_manager?

    candidates.each do |delivery|
      categories = []
      categories << :error if Deliveries::ErrorDetector.new(delivery).has_errors?
      categories << :service if delivery.requires_service_case_action?
      categories << :repair if delivery.repair_service? || delivery.requires_repair_service_action?
      categories << :sala_pickup if delivery.requires_sala_pickup?
      categories << :approval if can_see_approvals && !delivery.approved?
      next if categories.empty?

      items_by_id[delivery.id] = {delivery: delivery, categories: categories}
    end

    # Bodegaje por vencer: ventana de fecha distinta (warehousing_until, no
    # delivery_date), así que no cae dentro del scope de candidates de arriba.
    current_user_deliveries.warehousing_expiring_soon
      .includes(order: [:client, :seller])
      .each do |delivery|
        entry = (items_by_id[delivery.id] ||= {delivery: delivery, categories: []})
        entry[:categories] << :warehousing
      end

    # Reprogramaciones: vienen de notificaciones, no de delivery_date. Solo
    # las no leídas y cuya entrega siga activa — una notificación vieja de
    # una entrega ya entregada/cancelada/archivada no tiene nada que atender.
    fetch_reschedule_notifications.unread.each do |notification|
      delivery = notification.notifiable
      next unless delivery.is_a?(Delivery)
      next if delivery.status.in?(%w[delivered cancelled archived])

      entry = (items_by_id[delivery.id] ||= {delivery: delivery, categories: []})
      entry[:categories] << :reschedule unless entry[:categories].include?(:reschedule)
    end

    items_by_id.values.sort_by { |i| i[:delivery].delivery_date || Date.current }
  end

  def build_data_quality_issues
    issues = []

    vendors_without_hours = Vendor.left_joins(:vendor_business_hours)
      .where(vendor_business_hours: {id: nil}).distinct.count
    if vendors_without_hours > 0
      issues << {
        label: "#{vendors_without_hours} proveedor(es) sin horario de atención",
        url: admin_vendors_path
      }
    end

    stale_coordinates = DeliveryAddress.stuck_at_default_coordinates.count
    if stale_coordinates > 0
      issues << {
        label: "#{stale_coordinates} dirección(es) con coordenadas sin confirmar (nunca se movió el pin del mapa)",
        url: nil
      }
    end

    issues
  end

  def fetch_reschedule_notifications
    query = current_user.notifications.where(notification_type: "reschedule_delivery").recent

    if current_user.seller?
      query = query.joins("INNER JOIN deliveries ON notifications.notifiable_id = deliveries.id")
        .joins("INNER JOIN orders ON deliveries.order_id = orders.id")
        .where(orders: {seller_id: current_user.seller.id})
    end
    query
  end

  def current_user_deliveries
    case current_user.role
    when "seller"
      Delivery.joins(:order).where(orders: {seller: current_user.seller})
    else
      Delivery.all
    end
  end

  def current_user_orders
    current_user.seller? ? (current_user.seller&.orders || Order.none) : Order.all
  end

  def build_pending_tasks
    tasks = []

    case current_user.role
    when "seller"
      week_start = Date.current.next_week
      week_end = week_start.end_of_week

      next_week_deliveries = current_user_deliveries
        .where(delivery_date: Date.current.next_week..Date.current.next_week.end_of_week)
        .joins(:delivery_items)
        .where(delivery_items: {status: "pending"})
        .distinct.count

      if next_week_deliveries > 0
        tasks << {
          title: "Confirmar entregas próxima semana",
          description: "#{next_week_deliveries} entregas pendientes de confirmación",
          icon: "bi bi-calendar-check",
          color: "warning",
          action_text: "Confirmar",
          action_url: deliveries_path(q: {
            delivery_date_gteq: week_start,
            delivery_date_lteq: week_end,
            order_seller_seller_code_eq: current_user.seller.seller_code
          })
        }
      end

    when "production_manager"
      overdue_orders = Order.where(status: :in_production)
        .where("updated_at < ?", 7.days.ago).count

      if overdue_orders > 0
        tasks << {
          title: "Pedidos con retraso",
          description: "#{overdue_orders} pedidos llevan más de 7 días en producción",
          icon: "bi bi-exclamation-triangle",
          color: "danger",
          action_text: "Revisar",
          action_url: orders_path(q: {status_eq: "in_production"})
        }
      end

    when "logistics"
      unassigned_plans = DeliveryPlan.where(driver: nil, status: "draft").count

      if unassigned_plans > 0
        tasks << {
          title: "Planes sin conductor",
          description: "#{unassigned_plans} planes de entrega sin asignar",
          icon: "bi bi-person-x",
          color: "warning",
          action_text: "Asignar",
          action_url: delivery_plans_path
        }
      end
    end

    tasks
  end
end
