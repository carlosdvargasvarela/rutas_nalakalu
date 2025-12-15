# app/models/delivery_item.rb
class DeliveryItem < ApplicationRecord
  # ============================================================================
  # CONFIGURACIÓN Y RELACIONES
  # ============================================================================

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
    failed: 7
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
  scope :eligible_for_plan, -> { where.not(status: [:delivered, :cancelled, :rescheduled]) }
  scope :eligible_for_plan_for_others, -> { where.not(status: [:rescheduled]) }
  scope :loaded_items, -> { where(load_status: :loaded) }
  scope :unloaded_items, -> { where(load_status: :unloaded) }
  scope :missing_items, -> { where(load_status: :missing) }

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validate :order_item_must_be_ready_to_confirm, if: -> { status_changed?(from: "pending", to: "confirmed") }
  validates :order_item_id, uniqueness: {scope: :delivery_id, message: "ya existe en esta entrega"}

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  # Solo actualizamos el OrderItem tras cambios individuales
  # El estado del Delivery se recalcula explícitamente desde servicios
  after_update :update_order_item_status
  after_update :notify_reschedule, if: :saved_change_to_delivery_id?
  after_commit :recalculate_delivery_status, on: [:create, :update]

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
    else status.to_s.humanize
    end
  end

  def mark_loaded!
    update!(load_status: :loaded)
    delivery.recalculate_load_status!
  end

  def mark_unloaded!
    update!(load_status: :unloaded)
    delivery.recalculate_load_status!
  end

  def mark_missing!
    update!(load_status: :missing)
    delivery.recalculate_load_status!
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

  # Actualiza el estado del order_item basado en los delivery_items
  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
  end

  # Marca como entregado y actualiza el delivery
  def mark_as_delivered!
    transaction do
      update!(status: :delivered)
      delivery.update_status_based_on_items
    end
  end

  # Información para el reporte de logística
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
    # Descomenta si necesitas validar que el order_item esté "ready"
    # unless order_item.ready?
    #   errors.add(:base, "El producto aún no está listo para entrega (Producción no lo ha marcado como listo).")
    # end
  end

  # ============================================================================
  # MÉTODOS PRIVADOS
  # ============================================================================

  private

  # Notifica cuando un item es movido a otra entrega (reagendado)
  def notify_reschedule
    users = User.where(role: [:logistics, :admin]).to_a
    users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
    message = "El item '#{order_item.product}' del pedido #{order_item.order.number} fue reagendado para #{delivery.delivery_date.strftime("%d/%m/%Y")}."
    NotificationService.create_for_users(users.compact.uniq, self, message)
  end

  def recalculate_delivery_status
    return unless delivery.present?
    delivery.update_status_based_on_items
  end
end
