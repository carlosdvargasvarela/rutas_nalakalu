# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    # Cards resumen
    @pending_deliveries_count = current_user_deliveries.where(status: [ :scheduled, :ready_to_deliver ]).count
    @active_orders_count = current_user_orders.where(status: [ :pending, :in_production ]).count
    @upcoming_plans_count = upcoming_delivery_plans.count
    @unread_notifications_count = current_user.notifications.unread.count

    # Notificaciones recientes
    @recent_notifications = current_user.notifications.recent.limit(5)

    # Tareas pendientes según rol
    @pending_tasks = build_pending_tasks

    # Datos para gráfico (opcional)
    @chart_data = build_chart_data if current_user.admin? || current_user.production_manager?

    @deliveries_per_day = Delivery.where(status: :delivered, delivery_date: Date.current.beginning_of_week..Date.current.end_of_week).group_by_day(:delivery_date).count
    @orders_per_status = Order.group(:status).count
    @orders_per_seller = Seller.joins(:orders).where(orders: { status: [ :pending, :in_production ] }).group("sellers.name").count
    @deliveries_per_driver = User.where(role: :driver).left_joins(delivery_plans: { delivery_plan_assignments: :delivery }).group("users.name").count("deliveries.id")
    @orders_per_week = Order.group_by_week(:created_at, last: 8, format: "%d/%m").count
  end

  private

  def current_user_deliveries
    case current_user.role
    when "seller"
      Delivery.joins(:order).where(orders: { seller: current_user.seller })
    when "driver"
      Delivery.joins(:delivery_plan_assignments).where(delivery_plan_assignments: { delivery_plan: { driver: current_user } })
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
      # Entregas por confirmar próxima semana
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
          action_url: deliveries_path(q: { delivery_date_gteq: Date.current.next_week })
        }
      end

    when "production_manager"
      # Pedidos atrasados
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
      # Planes sin asignar
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
    # Datos básicos para el gráfico
    # Puedes expandir esto según tus necesidades
    {
      completed_this_week: 17,
      scheduled_this_week: 20,
      monthly_average: 92
    }
  end
end
