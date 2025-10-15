# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    if current_user&.role.to_s == "driver"
      redirect_to driver_delivery_plans_path and return
    end
    # Cards resumen
    @pending_deliveries_count = current_user_deliveries.where(status: [ :scheduled, :ready_to_deliver ]).count
    @active_orders_count = current_user_orders.where(status: [ :pending, :in_production ]).count
    @upcoming_plans_count = upcoming_delivery_plans.count
    @unread_notifications_count = current_user.notifications.unread.count
    @overdue_unplanned_deliveries =
      current_user_deliveries
        .overdue_unplanned
        .includes(order: [ :client, :seller ], delivery_address: :client)
        .order(delivery_date: :asc)
        .page(params[:page_overdue])
        .per(10)

    @overdue_deliveries_count =
      current_user_deliveries
        .overdue_unplanned
        .count

    # Notificaciones recientes
    @recent_notifications = current_user.notifications.recent.limit(5)

    if current_user.seller?
      # Solo notificaciones ligadas a sus pedidos
      @reschedule_notifications = current_user.notifications
        .joins("LEFT JOIN deliveries ON notifications.notifiable_id = deliveries.id AND notifications.notifiable_type = 'Delivery'")
        .joins("LEFT JOIN orders ON deliveries.order_id = orders.id")
        .where(notification_type: [ "reschedule_delivery" ])
        .where("orders.seller_id = ?", current_user.seller.id)
        .recent
        .page(params[:page_reschedules])
        .per(10)
    else
      # PM o Admin ven todas
      @reschedule_notifications = current_user.notifications
        .where(notification_type: [ "reschedule_delivery" ])
        .recent
        .page(params[:page_reschedules])
        .per(10)
    end

    # Tareas pendientes según rol
    @pending_tasks = build_pending_tasks

    # Datos para gráfico (opcional)
    @chart_data = build_chart_data if current_user.admin? || current_user.production_manager?

    @deliveries_per_day = Delivery.where(status: :delivered, delivery_date: Date.current.beginning_of_week..Date.current.end_of_week).group_by_day(:delivery_date).count
    @orders_per_status = Order.group(:status).count
    @orders_per_seller = Seller.joins(:orders).where(orders: { status: [ :pending, :in_production ] }).group("sellers.name").count
    @deliveries_per_driver = User.where(role: :driver).left_joins(delivery_plans: { delivery_plan_assignments: :delivery }).group("users.name").count("deliveries.id")
    @orders_per_week = Order.group_by_week(:created_at, last: 8, format: "%d/%m").count

    # Entregas de esta semana sin plan
    @unplanned_deliveries_this_week =
      current_user_deliveries
        .where(delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
        .available_for_plan
        .includes(order: [ :client, :seller ], delivery_address: :client)
        .order(:delivery_date)

    # Opcional: paginación si lo requieres
    # @unplanned_deliveries_this_week = @unplanned_deliveries_this_week.page(params[:page_unplanned]).per(10)

    # 🔥 Entregas reprogramadas con filtros y paginación
    if current_user.seller?
      @q_rescheduled = current_user_deliveries.rescheduled.ransack(params[:q])
      @rescheduled_deliveries = @q_rescheduled.result(distinct: true)
                                               .includes(order: [ :client, :seller ], delivery_address: :client)
                                               .page(params[:page])
                                               .per(10)
    elsif current_user.production_manager? || current_user.admin?
      # Tabla 1: Todas las entregas reagendadas
      @q_all_rescheduled = Delivery.rescheduled.ransack(params[:q_all])
      @rescheduled_deliveries = @q_all_rescheduled.result(distinct: true)
                                                   .includes(order: [ :client, :seller ], delivery_address: :client)
                                                   .page(params[:page_all])
                                                   .per(10)

      # Tabla 2: Reagendadas de esta semana
      @q_rescheduled_week = Delivery.rescheduled_this_week.ransack(params[:q_week])
      @rescheduled_this_week = @q_rescheduled_week.result(distinct: true)
                                                   .includes(order: [ :client, :seller ], delivery_address: :client)
                                                   .page(params[:page_week])
                                                   .per(10)
    end

    # Pendientes de aprobación
    if current_user.admin? || current_user.production_manager?
      @pending_approvals = Delivery.where(approved: false)
                                   .where("delivery_date BETWEEN ? AND ?", Date.current.beginning_of_week, Date.current.end_of_week)
                                   .order(:delivery_date)
    else
      @pending_approvals = []
    end
  end

  private

  def current_user_deliveries
    case current_user.role
    when "seller"
      Delivery.joins(:order).where(orders: { seller: current_user.seller })
    when "driver"
      Delivery
        .joins(delivery_plan_assignments: :delivery_plan)
        .where(delivery_plans: { driver_id: current_user.id })
    else
      Delivery.all
    end
  end

  def current_user_orders
    case current_user.role
    when "seller"
      current_user.seller&.orders || Order.none
    else
      Order.all
    end
  end

  def upcoming_delivery_plans
    current_week = Date.current.cweek
    current_year = Date.current.year
    DeliveryPlan.where(week: current_week..current_week + 2, year: current_year)
  end

  def build_pending_tasks
    tasks = []

    case current_user.role
    when "seller"
      week_start = Date.current.next_week
      week_end   = week_start.end_of_week

      next_week_deliveries = current_user_deliveries
        .where(delivery_date: Date.current.next_week..Date.current.next_week.end_of_week)
        .joins(:delivery_items)
        .where(delivery_items: { status: "pending" })
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
          action_url: orders_path(q: { status_eq: "in_production" })
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

  def build_chart_data
    {
      completed_this_week: 17,
      scheduled_this_week: 20,
      monthly_average: 92
    }
  end
end
