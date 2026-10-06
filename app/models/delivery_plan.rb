# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "draft" => "Borrador",
    "sent_to_logistics" => "Enviado a logística",
    "routes_created" => "Ruta creada",
    "in_progress" => "En progreso",
    "completed" => "Completado",
    "aborted" => "Abortado"
  }.freeze

  has_paper_trail
  belongs_to :load_closed_by, class_name: "User", optional: true
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_plan_locations, dependent: :destroy
  has_many :plan_events, dependent: :destroy
  belongs_to :driver, class_name: "User", optional: true
  belongs_to :last_recorded_by, class_name: "User", optional: true
  before_destroy :ensure_deletable

  after_create :record_created_event
  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  before_save :leave_draft_when_assigned
  after_update :record_status_change_event, if: :saved_change_to_status?
  before_destroy :flush_assignments

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
    Recoje_Sala: 7,
    Sala: 8
  }

  enum load_status: {
    empty: 0,
    partial: 1,
    all_loaded: 2,
    some_missing: 3
  }, _prefix: :load

  # Aliases de compatibilidad SIN prefijo
  def draft? = status_draft?
  def sent_to_logistics? = status_sent_to_logistics?
  def routes_created? = status_routes_created?
  def in_progress? = status_in_progress?
  def completed? = status_completed?
  def aborted? = status_aborted?

  def completed! = status_completed!

  validates :year, presence: true, numericality: {only_integer: true, greater_than: 2000}
  validates :week, presence: true, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 54}
  validates :status, presence: true

  scope :upcoming, -> {
    where("year > ? OR (year = ? AND week >= ?)", Date.current.year, Date.current.year, Date.current.cweek)
  }

  scope :ordered_by_first_delivery_desc, -> {
    joins(:deliveries)
      .group("delivery_plans.id")
      .order(Arel.sql("MIN(deliveries.delivery_date) DESC"))
  }

  scope :for_driver, ->(driver_id) { where(driver_id: driver_id) }
  scope :active, -> { where(status: [:routes_created, :in_progress]) }
  # Excluye planes compuestos ÚNICAMENTE por entregas reagendadas -- esos ya
  # no le sirven al conductor. Si tiene aunque sea una entregada, cancelada
  # o todavía pendiente, el plan se sigue mostrando (solo "puro reagendo"
  # se oculta).
  scope :with_pending_stops, -> {
    where(id: DeliveryPlan.joins(:deliveries).where.not(deliveries: {status: :rescheduled}).select(:id))
  }
  # Planes con GPS potencialmente útil en /tracking: en curso o ya completados
  # (el historial de recorrido de un plan completado sigue siendo consultable).
  scope :trackable, -> { where(status: [:routes_created, :in_progress, :completed]) }
  scope :with_deliveries_on, ->(date) { joins(:deliveries).where(deliveries: {delivery_date: date}).distinct }

  def stats
    {
      total_deliveries: deliveries.count,
      total_items: deliveries.joins(:delivery_items).merge(DeliveryItem.not_archived).count,
      service_cases: deliveries.joins(:delivery_items).merge(DeliveryItem.not_archived).where(delivery_items: {service_case: true}).count,
      confirmed_items: deliveries.joins(delivery_items: :order_item).merge(DeliveryItem.not_archived).where(order_items: {confirmed: true}).count
    }
  end

  # Recalcular estado de carga del plan (basado en items)
  def recalculate_load_status!
    all_items = DeliveryItem.not_archived.joins(:delivery)
      .where(deliveries: {id: delivery_ids})

    return if all_items.empty?

    loaded_count = all_items.where(load_status: DeliveryItem.load_statuses[:loaded]).count
    missing_count = all_items.where(load_status: DeliveryItem.load_statuses[:missing]).count
    total_count = all_items.count

    new_status = if missing_count > 0
      :some_missing
    elsif loaded_count == total_count
      :all_loaded
    elsif loaded_count > 0
      :partial
    else
      :empty
    end

    update!(load_status: new_status)
  end

  # @return [Boolean] true si la carga ya fue cerrada por un operario
  def load_closed?
    load_closed_at.present?
  end

  # Cierra la carga del camión y deja registro de quién y cuándo.
  def close_load!(user)
    update!(load_closed_at: Time.current, load_closed_by_id: user.id)
    PlanEvent.record(delivery_plan: self, action: "load_closed", actor: user, payload: load_stats)
  end

  def reopen_load!(user)
    update!(load_closed_at: nil, load_closed_by_id: nil)
    PlanEvent.record(delivery_plan: self, action: "load_reopened", actor: user)
  end

  # Paradas en orden de carga: la última parada se carga primero para que
  # la primera quede a la mano al descargar.
  def loading_assignments
    delivery_plan_assignments.reorder(stop_order: :desc)
  end

  # Marcar todo el plan como cargado
  def mark_all_loaded!
    transaction do
      DeliveryItem
        .joins(:delivery)
        .where(deliveries: {id: delivery_ids})
        .bulk_actionable
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .find_each do |item|
          item.update!(load_status: :loaded, status: :loaded_on_truck)
        end

      # Recalcular load_status y status de cada delivery (en memoria)
      deliveries.each do |delivery|
        delivery.recalculate_load_status!
        delivery.update_status_based_on_items
      end

      # Recalcular el estado de carga del plan una sola vez
      recalculate_load_status!
    end
  end

  # Porcentaje de carga del plan
  def load_percentage
    all_items = DeliveryItem.joins(:delivery).where(deliveries: {id: delivery_ids})
    total = all_items.count
    return 0 if total.zero?

    loaded = all_items.where(load_status: DeliveryItem.load_statuses[:loaded]).count
    ((loaded.to_f / total) * 100).round
  end

  # Estadísticas de carga
  def load_stats
    all_items = DeliveryItem.joins(:delivery).where(deliveries: {id: delivery_ids})

    {
      total_items: all_items.count,
      loaded_items: all_items.load_loaded.count,
      unloaded_items: all_items.load_unloaded.count,
      missing_items: all_items.load_missing.count,
      deliveries_all_loaded: deliveries.load_all_loaded.count,
      deliveries_with_missing: deliveries.load_some_missing.count,
      load_percentage: load_percentage
    }
  end

  def display_load_status
    case load_status
    when "empty" then "Sin cargar"
    when "partial" then "Parcialmente cargado"
    when "all_loaded" then "Completamente cargado"
    when "some_missing" then "Con faltantes"
    else load_status.to_s.humanize
    end
  end

  def first_delivery_date
    deliveries.minimum(:delivery_date)
  end

  # Ransacker mejorado para manejar casos donde no hay entregas
  ransacker :first_delivery_date do
    Arel.sql("(SELECT MIN(d.delivery_date)
               FROM deliveries d
               INNER JOIN delivery_plan_assignments dpa ON dpa.delivery_id = d.id
               WHERE dpa.delivery_plan_id = delivery_plans.id)")
  end

  def full_name
    "Plan de entregas semana #{week} - #{year}"
  end

  def total_deliveries
    deliveries.count
  end

  def service_case_deliveries
    deliveries.with_service_cases
  end

  def normal_deliveries
    deliveries.normal_deliveries
  end

  def add_delivery(delivery)
    delivery_plan_assignments.create!(delivery: delivery)
  end

  def ensure_deletable
    if status_in_progress? || status_completed? || status_aborted?
      errors.add(:base, "No se puede eliminar un plan en progreso, completado o abortado.")
      throw(:abort)
    end
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
    return false if delivery_plan_assignments.none?
    return false unless startable_today?
    update!(status: :in_progress)
  end

  # Por seguridad, la ruta solo debe poder arrancar el día que le corresponde:
  # arrancar antes ("me adelanté") o después ("se quedó pendiente de ayer")
  # es el típico error de campo que queremos bloquear.
  def startable_today?
    first_delivery_date.blank? || first_delivery_date == Date.current
  end

  def not_startable_today_message
    "Esta ruta es para el #{first_delivery_date.strftime('%d/%m/%Y')}, no podés iniciarla hoy."
  end

  def finish!
    return if status_completed?
    all_done = delivery_plan_assignments.all? { |a| a.completed? || a.cancelled? }
    update!(status: :completed) if all_done
  end

  # @return [Boolean] true si hay algo que #resync_status! pueda corregir:
  # (1) un assignment completed cuya delivery no llegó a un estado terminal
  # real (bug viejo de complete!, podía cerrar el plan de forma prematura),
  # (2) un assignment in_route/completed cuya delivery se quedó atrás con
  # items sueltos en pending/confirmed/in_plan (bug viejo de start!, que solo
  # avanzaba items exactamente :in_plan), o
  # (3) un assignment pending/in_route cuya delivery ya está rescheduled --
  # debió cancelarse solo vía Delivery#cancel_stale_assignment! y se quedó
  # atascado, bloqueando el cierre de toda la ruta.
  def status_needs_resync?
    delivery_plan_assignments.completed.any? { |a| !a.delivery.terminal? } ||
      delivery_plan_assignments.where.not(status: :pending).any? { |a| lagging_delivery?(a) } ||
      delivery_plan_assignments.where(status: [:pending, :in_route]).any? { |a| a.delivery.rescheduled? }
  end

  # Corrige los tres casos descritos en #status_needs_resync?, reabre el
  # plan si ya no le corresponde estar completed, e intenta cerrarlo si
  # ahora sí quedó todo en un estado terminal.
  # @return [Integer] cantidad de assignments/entregas corregidas
  def resync_status!
    fixed = 0

    transaction do
      delivery_plan_assignments.where.not(status: :pending).each do |a|
        next unless lagging_delivery?(a)

        a.delivery.delivery_items
          .where(status: DeliveryItem.statuses.values_at("pending", "confirmed", "in_plan"))
          .find_each { |item| item.update!(status: :in_route) }
        a.delivery.update_status_based_on_items
        fixed += 1
      end

      stuck_rescheduled = delivery_plan_assignments.where(status: [:pending, :in_route]).select { |a| a.delivery.rescheduled? }
      stuck_rescheduled.each { |a| a.update!(status: :cancelled, completed_at: Time.current) }
      fixed += stuck_rescheduled.size

      stale = delivery_plan_assignments.completed.reject { |a| a.delivery.terminal? }
      stale.each { |a| a.update!(status: :in_route) }
      fixed += stale.size

      update!(status: :in_progress) if status_completed? && stale.any?
      finish! if status_in_progress?
    end

    fixed
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

  def progress
    total = delivery_plan_assignments.count
    return 0 if total.zero?

    completed = delivery_plan_assignments.where(status: :completed).count
    ((completed.to_f / total) * 100).round
  end

  def service_cases_count
    deliveries.joins(:delivery_items)
      .where(delivery_items: {service_case: true})
      .unscope(:order)
      .distinct
      .count
  end

  private

  # @return [Boolean] true si el assignment ya arrancó/terminó pero su
  # delivery sigue mostrando un estado anterior a in_route
  def lagging_delivery?(assignment)
    assignment.delivery.status.in?(%w[scheduled ready_to_deliver in_plan])
  end

  STATUS_TO_PLAN_EVENT_ACTION = {
    "sent_to_logistics" => "sent_to_logistics",
    "routes_created" => "routes_created",
    "in_progress" => "started",
    "completed" => "finished",
    "aborted" => "aborted"
  }.freeze

  def record_created_event
    PlanEvent.record(delivery_plan: self, action: "created", actor: AuditActor.current)
  end

  def record_status_change_event
    action = STATUS_TO_PLAN_EVENT_ACTION[status]
    return unless action
    return if action == @recorded_plan_event_action

    @recorded_plan_event_action = action
    PlanEvent.record(delivery_plan: self, action: action, actor: AuditActor.current)
  end

  def notify_driver_assignment
    NotificationService.notify_route_assigned(self) if driver_id.present?
  end

  # Un plan nunca se queda en borrador: al tener camión o conductor pasa a
  # "ruta creada" (igual que "Enviar a logística").
  def leave_draft_when_assigned
    self.status = :routes_created if status_draft? && (driver_id.present? || truck.present?)
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
