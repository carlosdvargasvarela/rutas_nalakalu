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

    # KPIs Principales
    @pending_deliveries_count = current_user_deliveries.where(status: [:scheduled, :ready_to_deliver]).count
    @active_orders_count = current_user_orders.where(status: [:pending, :in_production]).count
    @upcoming_plans_count = upcoming_delivery_plans.count
    @unread_notifications_count = current_user.notifications.unread.count

    # 1. Entregas de esta semana sin plan
    @unplanned_this_week = current_user_deliveries
      .where(delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
      .available_for_plan
      .includes(order: [:client, :seller], delivery_address: :client)
      .order(:delivery_date)
      .page(params[:page_unplanned])
      .per(10)

    # 2. Entregas con Errores (Semana actual y siguiente) - OPTIMIZADO
    @deliveries_with_errors = detect_deliveries_with_errors
      .page(params[:page_errors])
      .per(10)

    # 3. Pendientes de aprobación (Admin/PM)
    @pending_approvals = if current_user.admin? || current_user.production_manager?
      Delivery.where(approved: false)
        .where(delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
        .includes(order: [:client, :seller])
        .order(:delivery_date)
        .page(params[:page_approvals])
        .per(10)
    else
      Delivery.none.page(1)
    end

    # 4. Notificaciones de Reschedule
    @reschedule_notifications = fetch_reschedule_notifications
      .page(params[:page_reschedules])
      .per(10)

    # 5. Tareas y Notificaciones generales
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

  def detect_deliveries_with_errors
    # Filtramos entregas solo en el rango solicitado: Semana actual y siguiente
    candidates = current_user_deliveries
      .where(delivery_date: @error_date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .includes(
        order: [:client, :seller, :order_items],
        delivery_address: :client,
        delivery_items: :order_item
      )
      .order(:delivery_date)

    # Identificamos IDs que tienen errores usando el Service Object
    ids_with_errors = candidates.select do |delivery|
      Deliveries::ErrorDetector.new(delivery).has_errors?
    end.map(&:id)

    # Retornamos una relación de ActiveRecord para que Kaminari pueda paginar
    current_user_deliveries
      .where(id: ids_with_errors)
      .includes(order: [:client, :seller], delivery_address: :client)
      .order(:delivery_date)
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

  def upcoming_delivery_plans
    DeliveryPlan.where(week: Date.current.cweek..Date.current.cweek + 1, year: Date.current.year)
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
