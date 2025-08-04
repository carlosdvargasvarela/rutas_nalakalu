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
    pending: 0,      # Aún no confirmado para entrega
    confirmed: 1,    # Confirmado para entregar
    in_route: 2,
    delivered: 3,
    rescheduled: 4,
    cancelled: 5
  }

  # ============================================================================
  # SCOPES
  # ============================================================================

  scope :service_cases, -> { where(service_case: true) }

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validate :order_item_must_be_ready_to_confirm, if: -> { status_changed?(from: "pending", to: "confirmed") }

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  before_update :prevent_edit_if_rescheduled
  after_update :notify_confirmation, if: :saved_change_to_status?
  after_update :notify_reschedule, if: :saved_change_to_delivery_id?
  after_update :notify_all_confirmed, if: :saved_change_to_status?
  after_update :update_order_item_status

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  # Actualiza el estado del order_item basado en los delivery_items
  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
  end

  # Actualiza el estado del delivery basado en los delivery_items
  def update_delivery_status
    delivery.update_status_based_on_items if delivery.present?
  end

  # Marca como entregado y actualiza el order_item
  def mark_as_delivered!
    transaction do
      update!(status: :delivered)
      order_item.check_delivery_status!
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

  # Reagenda este delivery_item
  def reschedule!(target_delivery: nil, new_date: nil)
    transaction do
      # 1. Marcar el original como reagendado
      update!(status: :rescheduled)

      # 2. Determinar el delivery destino
      delivery_destino = if target_delivery.present?
        target_delivery
      else
        # Si no se pasa uno, crear uno nuevo con los mismos datos
        Delivery.create!(
          order: delivery.order,
          delivery_address: delivery.delivery_address,
          delivery_date: new_date || delivery.delivery_date + 7.days, # Por defecto, una semana después
          contact_name: delivery.contact_name,
          contact_phone: delivery.contact_phone,
          contact_id: delivery.contact_id,
          status: :scheduled
        )
      end

      # 3. Crear el nuevo delivery_item
      DeliveryItem.create!(
        delivery: delivery_destino,
        order_item: order_item,
        quantity_delivered: quantity_delivered,
        status: :pending,
        service_case: service_case
      )
    end
  end

  # ============================================================================
  # VALIDACIONES PERSONALIZADAS
  # ============================================================================

  def order_item_must_be_ready_to_confirm
    unless order_item.ready?
      errors.add(:base, "El producto aún no está listo para entrega (Producción no lo ha marcado como listo).")
    end
  end

  # ============================================================================
  # MÉTODOS PRIVADOS
  # ============================================================================

  private

  # Previene la edición de items reagendados
  def prevent_edit_if_rescheduled
    if status_was == "rescheduled"
      errors.add(:base, "No se puede modificar un producto reagendado.")
      throw :abort
    end
  end

  # Notifica cuando todos los productos de una entrega están confirmados
  def notify_all_confirmed
    return unless status == "confirmed"

    delivery = self.delivery
    # Solo cuenta los delivery_items que siguen en este delivery
    all_confirmed = delivery.delivery_items.all? { |di| di.status == "confirmed" }

    if all_confirmed
      users = User.where(role: [ :logistics, :admin ])
      users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
      message = "Todos los productos del pedido #{delivery.order.number} para la entrega del #{delivery.delivery_date.strftime('%d/%m/%Y')} fueron confirmados por el vendedor."
      NotificationService.create_for_users(users.uniq, delivery, message)
    end
  end

  # Notifica cuando un item individual es confirmado
  def notify_confirmation
    if status == "confirmed"
      users = User.where(role: [ :logistics, :admin ])
      users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
      message = "El item '#{order_item.product}' del pedido #{order_item.order.number} fue confirmado por el vendedor."
      NotificationService.create_for_users(users.uniq, self, message)
    end
  end

  # Notifica cuando un item es reagendado
  def notify_reschedule
    users = User.where(role: [ :logistics, :admin ])
    users << delivery.delivery_plan.driver if delivery.delivery_plan&.driver
    message = "El item '#{order_item.product}' del pedido #{order_item.order.number} fue reagendado para #{delivery.delivery_date.strftime('%d/%m/%Y')}."
    NotificationService.create_for_users(users.uniq, self, message)
  end
end
