# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  belongs_to :driver, class_name: "User", optional: true

  enum status: { draft: 0, sent_to_logistics: 1, routes_created: 2 }

  validates :week, :year, presence: true

  # Scope para estadisticas rapidas para el dashboard
  def stats
    {
      total_deliveries: deliveries.count,
      total_items: deliveries.joins(:delivery_items).count,
      service_cases: deliveries.joins(:delivery_items).where(delivery_items: { service_case: true }).count,
      confirmed_items: deliveries.joins(:delivery_items => :order_item).where(order_items: { confirmed: true }).count
    }
  end
  
  # Nombre completo del plan
  def full_name
    "Plan de entregas semana #{week} - #{year}"
  end

  # Total de entregas en el plan
  def total_deliveries
    deliveries.count
  end

  # Entregas con casos de servicio
  def service_case_deliveries
    deliveries.with_service_cases
  end

  # Entregas normales
  def normal_deliveries
    deliveries.normal_deliveries
  end

  # Agregar entrega al plan
  def add_delivery(delivery)
    delivery_plan_assignments.create!(delivery: delivery)
  end

  # Enviar a logística
  def send_to_logistics!
    update!(status: :sent_to_logistics)
  end

  # Estadísticas del plan
  def statistics
    {
      total_deliveries: total_deliveries,
      service_cases: service_case_deliveries.count,
      normal_deliveries: normal_deliveries.count,
      total_items: deliveries.joins(:delivery_items).sum('delivery_items.quantity_delivered')
    }
  end
end