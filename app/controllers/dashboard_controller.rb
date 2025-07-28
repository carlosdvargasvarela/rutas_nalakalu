# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @pending_deliveries_count = Delivery.pending.count
    @active_orders_count = Order.active.count
    @upcoming_plans_count = DeliveryPlan.upcoming.count
    @dashboard_alerts = "Recuerda revisar los pedidos pendientes antes de finalizar la semana." # Opcional
  end
end