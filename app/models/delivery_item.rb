# La unidad mínima de entrega: un {OrderItem} dentro de una {Delivery}
# concreta. Su status avanza por el flujo operativo de la entrega
# (pending → confirmed → in_plan → in_route → delivered, con salidas a
# rescheduled/cancelled/failed) y sus cambios disparan, en cascada, el
# recálculo del status de {OrderItem} y de {Delivery} (ver callbacks abajo).
class DeliveryItem < ApplicationRecord
  include ActionView::RecordIdentifier
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "pending" => "Pendiente de confirmar",
    "confirmed" => "Confirmado",
    "in_plan" => "En plan de entregas",
    "in_route" => "En ruta",
    "delivered" => "Entregado",
    "rescheduled" => "Reprogramado",
    "cancelled" => "Cancelado",
    "failed" => "Entrega fracasada",
    "loaded_on_truck" => "Cargado en camión",
    "warehousing" => "En bodegaje"
  }.freeze

  has_paper_trail
  belongs_to :delivery
  belongs_to :order_item
  has_many :delivery_item_notes, dependent: :destroy

  accepts_nested_attributes_for :order_item

  # ============================================================================
  # ENUMS
  # ============================================================================

  enum status: {
    pending: 0,
    confirmed: 1,
    in_plan: 2,
    in_route: 3,
    delivered: 4,
    rescheduled: 5,
    cancelled: 6,
    failed: 7,
    loaded_on_truck: 8,
    warehousing: 9
  }

  enum load_status: {
    unloaded: 0,
    loaded: 1,
    missing: 2
  }, _prefix: :load

  # ============================================================================
  # SCOPES
  # ============================================================================

  # Estados que cualquier rol (no solo admin) puede ver en un plan ya armado.
  # cancelled/failed/rescheduled/warehousing quedan afuera porque confunden a
  # logística/vendedores — un producto cancelado no debería seguir
  # apareciendo como si fuera parte de la entrega.
  VISIBLE_TO_ALL_STATUSES = %w[pending confirmed in_plan in_route delivered loaded_on_truck].freeze

  scope :service_cases, -> { where(service_case: true) }
  scope :eligible_for_plan, -> { where.not(status: [:delivered, :cancelled, :rescheduled, :loaded_on_truck, :warehousing, :failed]) }
  scope :eligible_for_plan_for_others, -> { where(status: VISIBLE_TO_ALL_STATUSES) }
  scope :loaded_items, -> { where(load_status: :loaded) }
  scope :unloaded_items, -> { where(load_status: :unloaded) }
  scope :missing_items, -> { where(load_status: :missing) }
  scope :bulk_actionable, -> { where.not(status: %i[delivered rescheduled cancelled failed warehousing]) }
  scope :bulk_confirmable, -> { where(status: :pending) }
  scope :bulk_deconfirmable, -> { where(status: :confirmed) }
  scope :bulk_deliverable, -> { where(status: %i[pending confirmed in_plan in_route loaded_on_truck]) }
  scope :bulk_cancellable, -> { where(status: %i[pending confirmed in_plan]) }
  scope :bulk_reschedulable, -> { where(status: %i[pending confirmed in_plan]) }

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validates :order_item_id, uniqueness: {scope: :delivery_id, message: "ya existe en esta entrega"}

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  after_update :update_order_item_status
  after_update :notify_reschedule, if: :saved_change_to_delivery_id?
  after_commit :recalculate_delivery_status, on: [:create, :update]
  after_update :trigger_delivery_recalculation, if: :saved_change_to_load_status?
  after_update_commit :broadcast_item_row_update

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  # Marca el item como cargado en camión.
  #
  # @raise [StandardError] si el item no está en un estado bulk-actionable
  # @return [void]
  def mark_loaded!
    raise StandardError, "No se puede cargar un producto en estado #{status}." unless bulk_actionable?

    transaction do
      update!(load_status: :loaded, status: :loaded_on_truck)
      delivery.recalculate_load_status!
    end
  end

  # Revierte la carga: vuelve el item a load_status :unloaded y status :pending.
  #
  # @return [void]
  def mark_unloaded!
    transaction do
      update!(load_status: :unloaded, status: :pending)
      delivery.recalculate_load_status!
    end
  end

  # Marca el item como faltante al momento de cargar el camión.
  #
  # @return [void]
  def mark_missing!
    transaction do
      update!(load_status: :missing)
      delivery.recalculate_load_status!
    end
  end

  # @return [String] etiqueta legible del load_status
  def display_load_status
    case load_status
    when "unloaded" then "Sin cargar"
    when "loaded" then "Cargado"
    when "missing" then "Faltante"
    else load_status.to_s.humanize
    end
  end

  # @param user [User, nil]
  # @return [ActiveRecord::Relation<DeliveryItem>]
  def self.eligible_for_plan_for(user)
    return eligible_for_plan if user&.production_manager?
    eligible_for_plan_for_others
  end

  # @return [void]
  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
  end

  # @return [void]
  def mark_as_delivered!
    # No usar transaction aquí — el caller (Delivery#mark_as_delivered!) ya abre una
    update!(status: :delivered)
    # El callback after_commit :recalculate_delivery_status se encarga del resto
  end

  # Mismo criterio que el scope eligible_for_plan_for_others, pero sobre un
  # registro ya cargado en memoria (evita una query extra cuando se filtra
  # una colección ya preloaded, ej. delivery.delivery_items.select(&:visible_to_all?)).
  # @return [Boolean]
  def visible_to_all?
    status.in?(VISIBLE_TO_ALL_STATUSES)
  end

  # @return [Boolean] true si el status admite acciones masivas (bulk actions)
  def bulk_actionable?
    !status.in?(%w[delivered rescheduled cancelled failed warehousing])
  end

  # @return [Integer]
  def quantity
    quantity_delivered || 0
  end

  # @return [String]
  def product
    order_item.product
  end

  # @return [Boolean] true si tiene al menos una nota abierta
  def notes_open?
    delivery_item_notes.open.exists?
  end

  private

  # Notifica a logística/admin y al driver del plan (si hay) que el item fue reagendado.
  #
  # @return [void]
  def notify_reschedule
    users = User.where(role: [:logistics, :admin]).to_a
    users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
    message = "El item '#{order_item.product}' del pedido #{order_item.order.number} fue reagendado para #{delivery.delivery_date.strftime("%d/%m/%Y")}."
    NotificationService.create_for_users(users.compact.uniq, self, message)
  end

  # @return [void]
  def trigger_delivery_recalculation
    delivery&.recalculate_load_status!
  end

  # @return [void]
  def recalculate_delivery_status
    delivery&.update_status_based_on_items
  end

  # @return [void]
  def broadcast_item_row_update
    broadcast_replace_to(
      "delivery_#{delivery_id}_items",
      target: dom_id(self),
      partial: "deliveries/show_partials/product_item_row",
      locals: {item: self, delivery: delivery}
    )
  end
end
