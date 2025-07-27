# app/models/delivery_item.rb
class DeliveryItem < ApplicationRecord
  belongs_to :delivery
  belongs_to :order_item

  before_update :prevent_edit_if_rescheduled


  validates :quantity_delivered, presence: true, numericality: { greater_than: 0 }

  scope :service_cases, -> { where(service_case: true) }

  enum status: { pending: 0, confirmed: 1, in_route: 2, delivered: 3, rescheduled: 4, cancelled: 5, service_case: 6 }

  after_save :update_order_item_status

  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
  end

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

  private

  def prevent_edit_if_rescheduled
    if status_was == "rescheduled"
      errors.add(:base, "No se puede modificar un producto reagendado.")
      throw :abort
    end
  end
end
