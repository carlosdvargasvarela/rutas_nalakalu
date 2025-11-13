# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  # has_paper_trail # Temporalmente desactivado por bug en v16.0
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_plan_locations, dependent: :destroy
  belongs_to :driver, class_name: "User", optional: true
  before_destroy :ensure_deletable

  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?
  before_destroy :flush_assignments

  # 1) Enums con sintaxis posicional y prefix para evitar colisiones
  enum :status, {
    draft: 0,
    sent_to_logistics: 1,
    routes_created: 2,
    in_progress: 3,
    completed: 4,
    aborted: 5
  }, default: :draft, prefix: true

  enum :truck, {
    PRI: 0,
    PRU: 1,
    GRU: 2,
    GRI: 3,
    GRIR: 4,
    PickUp_Ricardo: 5,
    PickUp_Ruben: 6,
    Recoje_Sala: 7
  }

  # 2) Aliases de compatibilidad SIN prefijo (para no tocar vistas existentes)
  #    Esto habilita draft?, sent_to_logistics?, routes_created?, etc.
  def draft?            = status_draft?
  def sent_to_logistics? = status_sent_to_logistics?
  def routes_created?   = status_routes_created?
  def in_progress?      = status_in_progress?
  def completed?        = status_completed?
  def aborted?          = status_aborted?

  # 3) Aliases para setters de estado si en algún lugar se usan sin prefijo
  def draft!            = status_draft!
  def sent_to_logistics! = status_sent_to_logistics!
  def routes_created!   = status_routes_created!
  def in_progress!      = status_in_progress!
  def completed!        = status_completed!
  def aborted!          = status_aborted!

  validates :year, presence: true, numericality: { only_integer: true, greater_than: 2000 }
  validates :week, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 54 }
  validates :status, presence: true

  # Scope para estadisticas rapidas para el dashboard
  scope :upcoming, -> {
    where("year > ? OR (year = ? AND week >= ?)", Date.current.year, Date.current.year, Date.current.cweek)
  }

  scope :ordered_by_first_delivery_desc, -> {
    joins(:deliveries)
      .group("delivery_plans.id")
      .order(Arel.sql("MIN(deliveries.delivery_date) DESC"))
  }

  scope :for_driver, ->(driver_id) { where(driver_id: driver_id) }
  scope :active, -> { where(status: [ :routes_created, :in_progress ]) }

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
      "Ruta creada"
    when "in_progress"
      "En progreso"
    when "completed"
      "Completado"
    when "aborted"
      "Abortado"
    else
      "Desconocido"
    end
  end

  def first_delivery_date
    deliveries.minimum(:delivery_date)
  end

  # Ransacker para filtrar por el rango de fechas de la primera entrega
  ransacker :first_delivery_date do |parent|
    Arel.sql("(SELECT MIN(deliveries.delivery_date)
               FROM deliveries
               INNER JOIN delivery_plan_assignments dpa
               ON dpa.delivery_id = deliveries.id
               WHERE dpa.delivery_plan_id = delivery_plans.id)")
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
    update!(status: :routes_created)
  end

  def ensure_deletable
    # Evitamos borrar planes que ya están en progreso, completados o abortados
    if status_in_progress? || status_completed? || status_aborted?
      errors.add(:base, "No se puede eliminar un plan en progreso, completado o abortado.")
      throw(:abort)
    end
  end

  # NUEVO: Fallar todas las asignaciones pendientes o en ruta del plan
  def fail_all_pending_assignments!(reason:, failed_by:)
    transaction do
      delivery_plan_assignments.where(status: [ :pending, :in_route ]).find_each do |assignment|
        assignment.mark_as_failed!(reason: reason, failed_by: failed_by)
      end
      # Opcional: marcar el plan como abortado
      abort! unless status_completed?
    end
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
    %w[id week year status driver_id created_at updated_at truck first_delivery_date] + _ransackers.keys
  end

  def self.ransackable_associations(auth_object = nil)
    %w[driver deliveries delivery_plan_assignments]
  end

  def all_deliveries_confirmed?
    deliveries.all?(&:confirmed?) || deliveries.all?(&:in_plan?)
  end

  def truck_label
    truck.present? ? truck.to_s.tr("_", " ") : nil
  end

  def start!
    return if status_in_progress? || status_completed?
    update!(status: :in_progress)
  end

  def finish!
    return if status_completed?
    # Solo completar si todos los assignments están completed o cancelled
    all_done = delivery_plan_assignments.all? { |a| a.completed? || a.cancelled? }
    update!(status: :completed) if all_done
  end

  def abort!
    return if status_aborted? || status_completed?
    update!(status: :aborted)
  end

  def delivery_date
    deliveries.first&.delivery_date
  end

  def assignments
    delivery_plan_assignments.includes(:delivery)
  end

  # Progreso del plan (porcentaje de assignments completados)
  def progress
    total = delivery_plan_assignments.count
    return 0 if total.zero?

    completed = delivery_plan_assignments.where(status: :completed).count
    ((completed.to_f / total) * 100).round
  end

  private

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  def update_status_on_driver_change
    if driver_id.present?
      if all_deliveries_confirmed?
        update_column(:status, DeliveryPlan.statuses[:routes_created]) if status_draft?
      else
        errors.add(:base, "No puedes asignar a logística mientras existan entregas sin confirmar")
      end

      # si hay alguna entrega scheduled, siempre obligamos a draft
      self.status = :draft unless all_deliveries_confirmed?
    else
      update_column(:status, DeliveryPlan.statuses[:draft]) if status_sent_to_logistics?
    end
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
