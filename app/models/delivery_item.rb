class DeliveryItem < ApplicationRecord
  include ActionView::RecordIdentifier

  has_paper_trail
  belongs_to :delivery
  belongs_to :order_item

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
    loaded_on_truck: 8
  }

  enum load_status: {
    unloaded: 0,
    loaded: 1,
    missing: 2
  }, _prefix: :load

  # ============================================================================
  # SCOPES
  # ============================================================================

  scope :service_cases, -> { where(service_case: true) }
  scope :eligible_for_plan, -> { where.not(status: [:delivered, :cancelled, :rescheduled, :loaded_on_truck]) }
  scope :eligible_for_plan_for_others, -> { where.not(status: [:rescheduled]) }
  scope :loaded_items, -> { where(load_status: :loaded) }
  scope :unloaded_items, -> { where(load_status: :unloaded) }
  scope :missing_items, -> { where(load_status: :missing) }
  scope :bulk_actionable, -> { where.not(status: %i[delivered rescheduled cancelled failed]) }
  scope :bulk_confirmable, -> { where(status: :pending) }
  scope :bulk_deliverable, -> { where(status: %i[pending confirmed in_plan in_route loaded_on_truck]) }
  scope :bulk_cancellable, -> { where(status: %i[pending confirmed in_plan]) }
  scope :bulk_reschedulable, -> { where(status: %i[pending confirmed in_plan]) }

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validate :order_item_must_be_ready_to_confirm, if: -> { status_changed?(from: "pending", to: "confirmed") }
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

  def display_status
    case status
    when "pending" then "Pendiente de confirmar"
    when "confirmed" then "Confirmado"
    when "in_plan" then "En plan de entregas"
    when "in_route" then "En ruta"
    when "delivered" then "Entregado"
    when "rescheduled" then "Reprogramado"
    when "cancelled" then "Cancelado"
    when "failed" then "Entrega fracasada"
    when "loaded_on_truck" then "Cargado en camión"
    else status.to_s.humanize
    end
  end

  def mark_loaded!
    transaction do
      update!(load_status: :loaded, status: :loaded_on_truck)
      delivery.recalculate_load_status!
    end
  end

  def mark_unloaded!
    transaction do
      update!(load_status: :unloaded, status: :pending)
      delivery.recalculate_load_status!
    end
  end

  def mark_missing!
    transaction do
      update!(load_status: :missing)
      delivery.recalculate_load_status!
    end
  end

  def display_load_status
    case load_status
    when "unloaded" then "Sin cargar"
    when "loaded" then "Cargado"
    when "missing" then "Faltante"
    else load_status.to_s.humanize
    end
  end

  def self.eligible_for_plan_for(user)
    return eligible_for_plan if user&.production_manager?
    eligible_for_plan_for_others
  end

  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
  end

  def mark_as_delivered!
    # No usar transaction aquí — el caller (Delivery#mark_as_delivered!) ya abre una
    update!(status: :delivered)
    # El callback after_commit :recalculate_delivery_status se encarga del resto
  end

  def bulk_reschedulable?
    status.in?(%w[pending confirmed in_plan])
  end

  def logistics_info
    {
      product: order_item.product,
      quantity: quantity_delivered,
      service_case: service_case?
    }
  end

  def quantity
    quantity_delivered || 0
  end

  def product
    order_item.product
  end

  # ============================================================================
  # VALIDACIONES PERSONALIZADAS
  # ============================================================================

  def order_item_must_be_ready_to_confirm
    # unless order_item.ready?
    #   errors.add(:base, "El producto aún no está listo para entrega.")
    # end
  end

  private

  def notify_reschedule
    users = User.where(role: [:logistics, :admin]).to_a
    users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
    message = "El item '#{order_item.product}' del pedido #{order_item.order.number} fue reagendado para #{delivery.delivery_date.strftime("%d/%m/%Y")}."
    NotificationService.create_for_users(users.compact.uniq, self, message)
  end

  def trigger_delivery_recalculation
    delivery&.recalculate_load_status!
  end

  def recalculate_delivery_status
    delivery&.update_status_based_on_items
  end

  def broadcast_item_row_update
    broadcast_replace_to(
      "delivery_#{delivery_id}_items",
      target: dom_id(self),
      partial: "deliveries/show_partials/product_item_row",
      locals: {item: self, delivery: delivery}
    )
  end
end
