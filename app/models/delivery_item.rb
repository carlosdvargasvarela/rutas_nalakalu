# app/models/delivery_item.rb
class DeliveryItem < ApplicationRecord
  belongs_to :delivery
  belongs_to :order_item

  enum status: { pending: 0, delivered: 1, rescheduled: 2, cancelled: 3, service_case: 4 }

  validates :quantity_delivered, presence: true, numericality: { greater_than: 0 }

  scope :service_cases, -> { where(service_case: true) }

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