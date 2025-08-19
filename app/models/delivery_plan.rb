# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  has_paper_trail
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  belongs_to :driver, class_name: "User", optional: true

  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?

  enum status: { draft: 0, sent_to_logistics: 1, routes_created: 2 }

  validates :week, :year, presence: true

  # Scope para estadisticas rapidas para el dashboard
  scope :upcoming, -> {
    where("year > ? OR (year = ? AND week >= ?)", Date.current.year, Date.current.year, Date.current.cweek)
  }
  def stats
    {
      total_deliveries: deliveries.count,
      total_items: deliveries.joins(:delivery_items).count,
      service_cases: deliveries.joins(:delivery_items).where(delivery_items: { service_case: true }).count,
      confirmed_items: deliveries.joins(delivery_items: :order_item).where(order_items: { confirmed: true }).count
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
      total_items: deliveries.joins(:delivery_items).sum("delivery_items.quantity_delivered")
    }
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id week year status driver_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[driver deliveries delivery_plan_assignments]
  end

  private

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  def update_status_on_driver_change
    if driver_id.present?
      # Solo cambia si sigue en draft (evita pisar estados más avanzados)
      update_column(:status, DeliveryPlan.statuses[:sent_to_logistics]) if draft?
    else
      # Si se desasigna conductor, regresa a draft solo si estaba en sent_to_logistics
      update_column(:status, DeliveryPlan.statuses[:draft]) if sent_to_logistics?
    end
  end
end
