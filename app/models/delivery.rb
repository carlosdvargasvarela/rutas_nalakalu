class Delivery < ApplicationRecord
  include ActionView::RecordIdentifier

  has_paper_trail
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items
  has_one :delivery_plan_assignment, dependent: :destroy
  has_one :delivery_plan, through: :delivery_plan_assignment

  accepts_nested_attributes_for :delivery_items, allow_destroy: true

  before_validation :generate_tracking_token, on: :create
  after_update_commit :broadcast_delivery_updates

  delegate :latitude, :longitude, :address, :plus_code, to: :delivery_address, allow_nil: true
  delegate :client, to: :delivery_address, allow_nil: true

  def location
    {lat: latitude.to_f, lng: longitude.to_f}
  end

  def public_tracking_url
    Rails.application.routes.url_helpers.public_tracking_url(token: tracking_token)
  end

  # ============================================================================
  # ENUMS
  # ============================================================================

  enum :status, {
    scheduled: 0,
    ready_to_deliver: 1,
    in_plan: 2,
    in_route: 3,
    delivered: 4,
    rescheduled: 5,
    cancelled: 6,
    archived: 7,
    failed: 8,
    loaded_on_truck: 9,
    warehousing: 10
  }

  enum :delivery_type, {
    normal: 0,
    pickup_with_return: 1,
    return_delivery: 2,
    onsite_repair: 3,
    internal_delivery: 4,
    only_pickup: 5
  }

  enum :load_status, {
    empty: 0,
    partial: 1,
    all_loaded: 2,
    some_missing: 3
  }, prefix: :load

  # ============================================================================
  # CONSTANTES
  # ============================================================================

  SERVICE_CASE_TYPES = %w[pickup_with_return return_delivery onsite_repair only_pickup].freeze
  BULK_LOCKED_STATUSES = %w[delivered rescheduled cancelled archived failed warehousing].freeze

  # Estados terminales de items — no participan en el flujo activo
  ITEM_TERMINAL_STATUSES = %w[delivered cancelled rescheduled failed].freeze
  # Estados activos de items — determinan el estado de la entrega
  ITEM_ACTIVE_STATUSES = %w[pending confirmed in_plan in_route loaded_on_truck].freeze

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
      .where.not(status: [statuses[:delivered], statuses[:rescheduled], statuses[:cancelled], statuses[:loaded_on_truck]])
  }
  scope :eligible_for_plan, -> {
    where.not(status: [:delivered, :cancelled, :rescheduled, :in_plan, :in_route, :archived, :failed, :loaded_on_truck, :warehousing])
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
  scope :warehousing_expiring_soon, -> {
    where(status: :warehousing)
      .where(warehousing_until: Date.current..(Date.current + 8.days))
  }

  # ============================================================================
  # BULK ACTIONS
  # ============================================================================

  def bulk_locked?
    status.in?(BULK_LOCKED_STATUSES)
  end

  def bulk_available?
    !bulk_locked? && delivery_items.bulk_actionable.exists?
  end

  # ============================================================================
  # RANSACK
  # ============================================================================

  ransacker :status, formatter: proc { |v| statuses[v] } do |parent|
    parent.table[:status]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[delivery_date status delivery_type contact_name contact_phone delivery_notes delivery_time_preference reschedule_reason]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[order delivery_address delivery_items]
  end

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  def warehousing_expiring_soon?
    warehousing? && warehousing_until.present? && warehousing_until <= Date.current + 8.days
  end

  def warehousing_days_remaining
    return nil unless warehousing? && warehousing_until.present?
    (warehousing_until - Date.current).to_i
  end

  def start_warehousing!(until_date)
    update!(status: :warehousing, warehousing_until: until_date)
  end

  def end_warehousing!
    update!(status: :scheduled, warehousing_until: nil)
  end

  def client_name
    order.client.name
  end

  def order_number
    order.number
  end

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
    when "loaded_on_truck" then "Cargada en camión"
    when "warehousing" then "En bodegaje"
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

  def recalculate_load_status!
    items = delivery_items.reload
    return if items.empty?

    loaded_count = items.load_loaded.count
    missing_count = items.load_missing.count
    total_count = items.count

    new_load_status = if missing_count > 0
      :some_missing
    elsif loaded_count == total_count
      :all_loaded
    elsif loaded_count > 0
      :partial
    else
      :empty
    end

    if new_load_status == :all_loaded
      update(load_status: new_load_status, status: :loaded_on_truck)
    else
      update(load_status: new_load_status)
    end
  end

  def mark_all_loaded!
    transaction do
      delivery_items
        .where.not(load_status: DeliveryItem.load_statuses[:missing])
        .update_all(
          load_status: DeliveryItem.load_statuses[:loaded],
          status: DeliveryItem.statuses[:loaded_on_truck],
          updated_at: Time.current
        )
      recalculate_load_status!
      update_status_based_on_items
    end
  end

  def address_error?
    Deliveries::ErrorDetector.new(self).errors.any? { |e| e[:category] == "Dirección" }
  end

  def reset_load_status!
    transaction do
      delivery_items.update_all(
        load_status: DeliveryItem.load_statuses[:unloaded],
        updated_at: Time.current
      )
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

  def load_percentage
    total = delivery_items.count
    return 0 if total.zero?
    loaded = delivery_items.load_loaded.count
    ((loaded.to_f / total) * 100).round
  end

  def sala_pickup_items
    @sala_pickup_items ||= Deliveries::SalaPickupDetector.new(self).actionable_items
  end

  def items_by_sala
    @items_by_sala ||= Deliveries::SalaPickupDetector.new(self).items_by_sala
  end

  def service_case_items
    @service_case_items ||= Deliveries::ServiceCaseDetector.new(self).actionable_items
  end

  def requires_service_case_action?
    service_case_items.any?
  end

  def requires_sala_pickup?
    sala_pickup_items.any?
  end

  # ============================================================================
  # RECÁLCULO DE ESTADO BASADO EN ITEMS
  # ============================================================================

  # Punto de entrada principal. Siempre refleja el estado real de los items.
  # No bloquea por estado actual de la entrega (excepto archived/warehousing).
  def update_status_based_on_items
    return if archived? || warehousing?

    item_statuses = delivery_items.reload.map(&:status)
    return if item_statuses.empty?

    new_status = calculate_delivery_status(item_statuses)
    return if new_status.blank? || new_status.to_s == status.to_s

    update!(status: new_status)
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
      delivery_items
        .where(status: %i[pending confirmed in_plan in_route loaded_on_truck])
        .find_each(&:mark_as_delivered!)

      reload

      # Forzar delivered si todos los items lo están
      if delivery_items.reload.where.not(status: :delivered).none?
        update!(status: :delivered)
      else
        update_status_based_on_items
      end
    end
  end

  def confirmed?
    order_items.all? { |oi| oi.status == "ready" }
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
    when :delivery then Delivery.statuses.key(status_value).humanize
    when :order then Order.statuses.key(status_value).humanize
    else status_value.to_s.humanize
    end
  end

  # ============================================================================
  # MÉTODOS DE CLASE
  # ============================================================================

  def self.status_options_for_select
    statuses.keys.map { |s| [Delivery.new(status: s).display_status, s.to_s] }
  end

  def self.to_csv(scope = all)
    CSV.generate(headers: true) do |csv|
      csv << ["Fecha de entrega", "Pedido", "Producto", "Cantidad", "Vendedor", "Cliente", "Dirección", "Estado", "Tipo"]
      scope.includes(order: [:client, :seller], delivery_address: :client, delivery_items: {order_item: :order}).find_each do |delivery|
        delivery.delivery_items.each do |di|
          csv << [
            delivery.delivery_date.strftime("%d/%m/%Y"),
            delivery.order.number,
            di.order_item.product,
            di.order_item.quantity,
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
  # CONFIRMACIÓN POR VENDEDOR
  # ============================================================================

  def mark_as_confirmed_by_vendor!(_user = nil)
    update!(
      confirmed_by_vendor: true,
      confirmed_by_vendor_at: Time.current,
      status: :ready_to_deliver
    )
  end

  def unconfirm_by_vendor!
    update!(confirmed_by_vendor: false, confirmed_by_vendor_at: nil)
    Rails.logger.info "[Delivery##{id}] Confirmación de vendedor removida"
  end

  def self.unconfirmed_by_vendor
    where(confirmed_by_vendor: false)
  end

  private

  # ============================================================================
  # CÁLCULO DE ESTADO — lógica centralizada
  # ============================================================================
  #
  # Jerarquía de decisión:
  #   1. Todos los items en el mismo estado terminal → ese estado
  #   2. Todos terminales pero mezclados → rescheduled > delivered > cancelled > failed
  #   3. Hay items activos → flujo operativo (in_route > loaded_on_truck > confirmed/in_plan > pending)
  #   4. Mezcla activos + terminales → se decide por los activos (los terminales son histórico)
  #
  def calculate_delivery_status(raw_statuses)
    statuses = raw_statuses.map(&:to_s)

    # ── 1. Todos iguales ──────────────────────────────────────────────────────
    return :delivered if statuses.all? { |s| s == "delivered" }
    return :cancelled if statuses.all? { |s| s == "cancelled" }
    return :rescheduled if statuses.all? { |s| s == "rescheduled" }
    return :failed if statuses.all? { |s| s == "failed" }

    # ── 2. Todos terminales pero mezclados ────────────────────────────────────
    if statuses.all? { |s| ITEM_TERMINAL_STATUSES.include?(s) }
      return :rescheduled if statuses.any? { |s| s == "rescheduled" }
      return :delivered if statuses.any? { |s| s == "delivered" }
      return :cancelled if statuses.any? { |s| s == "cancelled" }
      return :failed
    end

    # ── 3 & 4. Hay items activos — los terminales son solo histórico ──────────
    active = statuses.select { |s| ITEM_ACTIVE_STATUSES.include?(s) }

    # in_route tiene máxima prioridad operativa
    return :in_route if active.any? { |s| s == "in_route" }

    # cargado en camión
    return :loaded_on_truck if active.any? { |s| s == "loaded_on_truck" }

    # todos los activos están confirmados o en plan
    if active.all? { |s| %w[confirmed in_plan].include?(s) }
      if delivery_plan.present?
        return :in_plan
      else
        mark_as_confirmed_by_vendor! unless ready_to_deliver?
        return :ready_to_deliver
      end
    end

    # mezcla pending + confirmed → volver a scheduled (hay items sin confirmar)
    return :scheduled if active.any? { |s| s == "pending" }

    # fallback seguro
    :scheduled
  end

  def generate_tracking_token
    self.tracking_token ||= SecureRandom.urlsafe_base64(32)
  end

  # ============================================================================
  # TURBO STREAM BROADCASTING
  # ============================================================================

  def broadcast_delivery_updates
    broadcast_replace_to(
      "deliveries",
      target: dom_id(self, :card),
      partial: "deliveries/index_partials/delivery_card",
      locals: {delivery: self}
    )

    broadcast_replace_to(
      "delivery_#{id}_detail",
      target: "delivery_detail_header_#{id}",
      partial: "deliveries/show_partials/detail_header",
      locals: {
        delivery: self,
        can_edit: true,
        can_approve: true,
        can_reassign_seller: true,
        can_new_service_case: true,
        is_admin: true
      }
    )
  end
end
