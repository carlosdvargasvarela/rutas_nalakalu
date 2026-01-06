# app/models/delivery_plan.rb
class DeliveryPlan < ApplicationRecord
  has_paper_trail
  has_many :delivery_plan_assignments, -> { order(:stop_order) }, dependent: :destroy
  has_many :deliveries, through: :delivery_plan_assignments
  has_many :delivery_plan_locations, dependent: :destroy
  belongs_to :driver, class_name: "User", optional: true
  before_destroy :ensure_deletable

  after_update :notify_driver_assignment, if: :saved_change_to_driver_id?
  after_update :update_status_on_driver_change, if: :saved_change_to_driver_id?
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
    Recoje_Sala: 7
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

  def draft! = status_draft!
  def sent_to_logistics! = status_sent_to_logistics!
  def routes_created! = status_routes_created!
  def in_progress! = status_in_progress!
  def completed! = status_completed!
  def aborted! = status_aborted!

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

  def stats
    {
      total_deliveries: deliveries.count,
      total_items: deliveries.joins(:delivery_items).count,
      service_cases: deliveries.joins(:delivery_items).where(delivery_items: {service_case: true}).count,
      confirmed_items: deliveries.joins(delivery_items: :order_item).where(order_items: {confirmed: true}).count
    }
  end

  def display_status
    case status
    when "draft" then "Borrador"
    when "sent_to_logistics" then "Enviado a logística"
    when "routes_created" then "Ruta creada"
    when "in_progress" then "En progreso"
    when "completed" then "Completado"
    when "aborted" then "Abortado"
    else "Desconocido"
    end
  end

  # Recalcular estado de carga del plan (basado en items)
  def recalculate_load_status!
    all_items = DeliveryItem.joins(:delivery)
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

    update_column(:load_status, DeliveryPlan.load_statuses[new_status])

    if new_status == :all_loaded && !status_completed?
      status_completed!
    end
  end

  # Marcar todo el plan como cargado
  # Usa update_all para eficiencia y solo recalcula el plan UNA vez al final
  def mark_all_loaded!
    transaction do
      # 1. Actualizar todos los delivery_items de todas las deliveries del plan
      DeliveryItem
        .joins(:delivery)
        .where(deliveries: {id: delivery_ids})
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .update_all(
          load_status: DeliveryItem.load_statuses[:loaded],
          status: DeliveryItem.statuses[:loaded_on_truck],
          updated_at: Time.current
        )

      # 2. Recalcular load_status y status de cada delivery (en memoria)
      deliveries.each do |delivery|
        delivery.recalculate_load_status!
        delivery.update_status_based_on_items
      end

      # 3. Recalcular el estado de carga del plan una sola vez
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

  def send_to_logistics!
    update!(status: :routes_created)
  end

  def ensure_deletable
    if status_in_progress? || status_completed? || status_aborted?
      errors.add(:base, "No se puede eliminar un plan en progreso, completado o abortado.")
      throw(:abort)
    end
  end

  def fail_all_pending_assignments!(reason:, failed_by:)
    transaction do
      delivery_plan_assignments.where(status: [:pending, :in_route]).find_each do |assignment|
        assignment.mark_as_failed!(reason: reason, failed_by: failed_by)
      end
      abort! unless status_completed?
    end
  end

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

      self.status = :draft unless all_deliveries_confirmed?
    elsif status_sent_to_logistics?
      update_column(:status, DeliveryPlan.statuses[:draft])
    end
  end

  def flush_assignments
    delivery_plan_assignments.destroy_all
  end
end
