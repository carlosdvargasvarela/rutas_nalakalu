# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  has_paper_trail
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  belongs_to :driver, class_name: "User", optional: true

  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?
  before_save :force_draft_if_unconfirmed
  before_destroy :flush_assignments

  enum status: { draft: 0, sent_to_logistics: 1, routes_created: 2 }

  enum truck: { PRI: 0, PRU: 1, GRU: 2, GRI: 3 }

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

  def display_status
    case status
    when "draft"
      "Borrador"
    when "sent_to_logistics"
      "Enviado a logística"
    when "routes_created"
      "Rutas creada"
    else
      "Desconocido"
    end
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
    %w[id week year status driver_id created_at updated_at truck] + _ransackers.keys
  end

  def self.ransackable_associations(auth_object = nil)
    %w[driver deliveries delivery_plan_assignments]
  end

  def all_deliveries_confirmed?
    deliveries.all?(&:confirmed?)
  end

  private

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  def update_status_on_driver_change
    if driver_id.present?
      if all_deliveries_confirmed?
        update_column(:status, DeliveryPlan.statuses[:sent_to_logistics]) if draft?
      else
        # fallback: dejar en draft y quizás notificar al usuario
        update_column(:status, DeliveryPlan.statuses[:draft])
      end
    else
      update_column(:status, DeliveryPlan.statuses[:draft]) if sent_to_logistics?
    end
  end

  def force_draft_if_unconfirmed
    if driver_id.present? && !all_deliveries_confirmed?
      errors.add(:base, "No puedes asignar un conductor mientras existan entregas sin confirmar")
      throw(:abort)
    end

    # si hay alguna entrega scheduled, siempre obligamos a draft
    self.status = :draft unless all_deliveries_confirmed?
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
