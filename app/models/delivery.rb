# app/models/delivery.rb
class Delivery < ApplicationRecord
  has_paper_trail
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items
  has_many :delivery_plan_assignments, dependent: :destroy
  has_many :delivery_plans, through: :delivery_plan_assignments

  accepts_nested_attributes_for :delivery_items, allow_destroy: true

  # Delegar coordenadas directamente al delivery_address
  delegate :latitude, :longitude, :address, :plus_code, to: :delivery_address, allow_nil: true

  # Si quieres también el nombre del cliente:
  delegate :client, to: :delivery_address, allow_nil: true

  # Ejemplo de helper útil para Google Maps/JSON APIs
  def location
    {lat: latitude.to_f, lng: longitude.to_f}
  end

  # ============================================================================
  # ENUMS
  # ============================================================================

  enum status: {
    scheduled: 0,
    ready_to_deliver: 1,
    in_plan: 2,
    in_route: 3,
    delivered: 4,
    rescheduled: 5,
    cancelled: 6,
    archived: 7,
    failed: 8
  }

  enum delivery_type: {
    normal: 0,
    pickup_with_return: 1,
    return_delivery: 2,
    onsite_repair: 3,
    internal_delivery: 4,
    only_pickup: 5
  }

  enum load_status: {
    empty: 0,
    partial: 1,
    all_loaded: 2,
    some_missing: 3
  }, _prefix: :load

  # ============================================================================
  # CONSTANTES
  # ============================================================================

  SERVICE_CASE_TYPES = %w[pickup_with_return return_delivery onsite_repair only_pickup].freeze

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validates :delivery_date, presence: true

  # ============================================================================
  # SCOPES
  # ============================================================================

  scope :service_cases, -> { where(delivery_type: SERVICE_CASE_TYPES) }
  scope :normal_deliveries, -> { where(delivery_type: :normal) }
  scope :pending, -> { where(status: [:scheduled, :ready_to_deliver, :in_route]) }
  scope :overdue, -> {
    where("delivery_date < ?", Date.current)
      .where.not(status: [statuses[:delivered], statuses[:rescheduled], statuses[:cancelled]])
  }
  scope :eligible_for_plan, -> {
    where.not(status: [:delivered, :cancelled, :rescheduled, :in_plan, :in_route, :archived, :failed])
  }
  scope :not_assigned_to_plan, -> { where.not(id: DeliveryPlanAssignment.select(:delivery_id)) }
  scope :available_for_plan, -> { eligible_for_plan.not_assigned_to_plan }
  scope :rescheduled_this_week, -> {
    where(status: :rescheduled, delivery_date: Date.current.beginning_of_week..Date.current.end_of_week)
  }
  scope :overdue_unplanned, -> {
    where("delivery_date < ?", Date.current)
      .eligible_for_plan
      .not_assigned_to_plan
  }
  scope :for_week, ->(date) {
    week = date.cweek
    year = date.cwyear
    where("EXTRACT(week FROM delivery_date) = ? AND EXTRACT(year FROM delivery_date) = ?", week, year)
  }
  scope :with_service_cases, -> {
    joins(:delivery_items).where(delivery_items: {service_case: true}).distinct
  }

  # ============================================================================
  # RANSACK
  # ============================================================================

  ransacker :status, formatter: proc { |v| statuses[v] } do |parent|
    parent.table[:status]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[delivery_date status delivery_type contact_name contact_phone delivery_notes delivery_time_preference reschedule_reason]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[order delivery_address delivery_items]
  end

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  def service_case?
    delivery_type.in?(SERVICE_CASE_TYPES)
  end

  def display_status
    case status
    when "scheduled" then "Pendiente de confirmar"
    when "ready_to_deliver" then "Confirmada para entregar"
    when "in_plan" then "En plan"
    when "in_route" then "En ruta"
    when "delivered" then "Entregada"
    when "rescheduled" then "Reprogramada"
    when "cancelled" then "Cancelada"
    when "archived" then "Archivada"
    when "failed" then "Entrega fracasada"
    else status.to_s.humanize
    end
  end

  def display_type
    case delivery_type
    when "normal" then "Entrega normal"
    when "pickup_with_return" then "Recogida de producto y posteriormente entrega al cliente"
    when "return_delivery" then "Devolución de producto"
    when "onsite_repair" then "Reparación en sitio"
    when "only_pickup" then "Solo recogida de producto"
    when "internal_delivery" then "Mandado Interno"
    else delivery_type.to_s.humanize
    end
  end

  # Método para recalcular estado de carga basado en items
  def recalculate_load_status!
    items = delivery_items.reload
    return if items.empty?

    loaded_count = items.load_loaded.count
    missing_count = items.load_missing.count
    total_count = items.count

    new_status = if missing_count > 0
      :some_missing
    elsif loaded_count == total_count
      :all_loaded
    elsif loaded_count > 0
      :partial
    else
      :empty
    end

    update_column(:load_status, Delivery.load_statuses[new_status])
  end

  # Marcar toda la entrega como cargada
  def mark_all_loaded!
    transaction do
      delivery_items.where.not(load_status: DeliveryItem.load_statuses[:missing])
        .update_all(load_status: DeliveryItem.load_statuses[:loaded], updated_at: Time.current)
      recalculate_load_status!
    end
  end

  # Resetear carga de la entrega
  def reset_load_status!
    transaction do
      delivery_items.update_all(load_status: DeliveryItem.load_statuses[:unloaded], updated_at: Time.current)
      recalculate_load_status!
    end
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

  # Porcentaje de carga
  def load_percentage
    total = delivery_items.count
    return 0 if total.zero?

    loaded = delivery_items.load_loaded.count
    ((loaded.to_f / total) * 100).round
  end

  # Recalcula el estado de la entrega basándose en los estados de sus items
  # Debe invocarse explícitamente desde servicios/controladores tras cambios masivos
  def update_status_based_on_items
    statuses = delivery_items.pluck(:status).map(&:to_s)

    # Casos donde NO debemos actualizar
    return if archived?
    return if statuses.empty?

    # Si está en plan/ruta y todos los items están OK (no cancelados/reprogramados/fallidos),
    # solo actualizar si TODOS están entregados
    if (in_plan? || in_route?) && delivery_plans.exists?
      has_problems = statuses.any? { |s| %w[cancelled rescheduled failed].include?(s) }
      all_delivered = statuses.all? { |s| s == "delivered" }

      # Solo actualizar si hay problemas O si todo está entregado
      return unless has_problems || all_delivered
    end

    # Actualización de estado según prioridad
    new_status = calculate_delivery_status(statuses)
    update_column(:status, Delivery.statuses[new_status]) if new_status
  end

  def active_items_for_plan
    delivery_items.eligible_for_plan
  end

  def active_items_for_plan_for(user)
    delivery_items.merge(DeliveryItem.eligible_for_plan_for(user))
  end

  def has_service_cases?
    delivery_items.any?(&:service_case?)
  end

  def total_items
    delivery_items.sum(:quantity_delivered)
  end

  def mark_as_delivered!
    transaction do
      # Solo marcar como entregados los no terminales
      delivery_items.where(status: [:pending, :confirmed, :in_plan, :in_route]).find_each(&:mark_as_delivered!)

      # Recalcular el estado con la lógica nueva (no forzar a delivered siempre)
      update_status_based_on_items

      # Si tras el recálculo todos los items quedaron delivered, aseguramos el estado
      if delivery_items.where.not(status: :delivered).none?
        update_column(:status, Delivery.statuses[:delivered])
      end
    end
  end

  def confirmed?
    order_items.all? { |oi| oi.status == "ready" }
  end

  def delivery_plan
    delivery_plans.first
  end

  def delivery_history
    order.deliveries
      .where(delivery_address_id: delivery_address_id)
      .includes(delivery_items: :order_item)
      .order(:delivery_date)
  end

  def client_info
    {
      name: order.client.name,
      address: delivery_address.address,
      contact: contact_name,
      phone: contact_phone,
      seller: order.seller.name
    }
  end

  def status_humanize
    status.humanize
  end

  def delivery_type_humanize
    delivery_type.humanize
  end

  def status_i18n(status_value, type)
    case type
    when :delivery
      Delivery.statuses.key(status_value).humanize
    when :order
      Order.statuses.key(status_value).humanize
    else
      status_value.to_s.humanize
    end
  end

  # ============================================================================
  # MÉTODOS DE CLASE
  # ============================================================================

  def self.status_options_for_select
    statuses.keys.map do |s|
      [Delivery.new(status: s).display_status, s.to_s]
    end
  end

  def self.to_csv(scope = all)
    CSV.generate(headers: true) do |csv|
      csv << ["Fecha de entrega", "Pedido", "Producto", "Cantidad", "Vendedor", "Cliente", "Dirección", "Estado", "Tipo"]
      scope.includes(order: [:client, :seller], delivery_address: :client, delivery_items: {order_item: :order}).find_each do |delivery|
        delivery.delivery_items.each do |delivery_item|
          csv << [
            delivery.delivery_date.strftime("%d/%m/%Y"),
            delivery.order.number,
            delivery_item.order_item.product,
            delivery_item.order_item.quantity,
            delivery.order.seller.seller_code,
            delivery.order.client.name,
            delivery.delivery_address.address,
            delivery.status_humanize,
            delivery.delivery_type_humanize
          ]
        end
      end
    end
  end

  # ============================================================================
  # MÉTODOS PARA CONFIRMACIÓN POR VENDEDOR
  # ============================================================================

  def mark_as_confirmed_by_vendor!(user = nil)
    update!(
      confirmed_by_vendor: true,
      confirmed_by_vendor_at: Time.current
    )
    Rails.logger.info "[Delivery##{id}] Confirmada por vendedor#{" (#{user.email})" if user}"
  end

  def unconfirm_by_vendor!
    update!(
      confirmed_by_vendor: false,
      confirmed_by_vendor_at: nil
    )
    Rails.logger.info "[Delivery##{id}] Confirmación de vendedor removida"
  end

  # Scope para reportes
  def self.unconfirmed_by_vendor
    where(confirmed_by_vendor: false)
  end

  # ============================================================================
  # MÉTODOS PRIVADOS
  # ============================================================================

  private

  def calculate_delivery_status(statuses)
    statuses = statuses.map(&:to_s)

    terminal = %w[delivered cancelled rescheduled failed]
    non_terminal = %w[pending confirmed in_plan in_route]

    # 1) Uniformidad terminal
    return :delivered if statuses.all? { |s| s == "delivered" }
    return :cancelled if statuses.all? { |s| s == "cancelled" }
    return :rescheduled if statuses.all? { |s| s == "rescheduled" }
    return :failed if statuses.all? { |s| s == "failed" }

    # 2) Caso mixto: separar terminales vs no terminales
    non_terminal_statuses = statuses.select { |s| non_terminal.include?(s) }
    terminal_statuses = statuses.select { |s| terminal.include?(s) }

    # 2.a) Si NO hay no terminales (todos son terminales pero mixtos):
    # Regla especial: si hay al menos un delivered entre los terminales, la entrega debe ser delivered.
    if non_terminal_statuses.empty?
      return :delivered if terminal_statuses.any? { |s| s == "delivered" }
      # Si no hay delivered, no cambiar (porque no son uniformes para cancelled/rescheduled/failed)
      return nil
    end

    # 2.b) Sí hay no terminales → decidir SOLO con no terminales
    # Prioridad: in_route si alguno
    return :in_route if non_terminal_statuses.any? { |s| s == "in_route" }

    # Todos los no terminales confirmed → confirmado para entregar
    if non_terminal_statuses.all? { |s| s == "confirmed" }
      unless delivery_plans.exists?
        mark_as_confirmed_by_vendor!
      end
      return delivery_plans.exists? ? :in_plan : :ready_to_deliver
    end

    # Todos los no terminales pending → scheduled
    return :scheduled if non_terminal_statuses.all? { |s| s == "pending" }

    # Cualquier otra mezcla de no terminales → no cambiar
    nil
  end
end
