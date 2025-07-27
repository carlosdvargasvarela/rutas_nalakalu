# app/models/delivery_item.rb
class DeliveryItem < ApplicationRecord
  belongs_to :delivery
  belongs_to :order_item

  validates :quantity_delivered, presence: true, numericality: { greater_than: 0 }

  scope :service_cases, -> { where(service_case: true) }

  enum status: { pending: 0, confirmed: 1, in_route: 2, delivered: 3, rescheduled: 4, cancelled: 5, service_case: 6 }

  after_save :update_order_item_status

  def update_order_item_status
    order_item.update_status_based_on_deliveries if order_item.present?
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
end