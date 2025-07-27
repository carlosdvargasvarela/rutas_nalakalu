# app/models/order_item.rb
class OrderItem < ApplicationRecord
  belongs_to :order
  has_many :delivery_items, dependent: :destroy

  enum status: { pending: 0, ready: 1, delivered: 2, rescheduled: 3, cancelled: 4, service_case: 5 }

  validates :product, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  scope :to_be_confirmed, -> { where(confirmed: [nil, false]) }
  scope :confirmed, -> { where(confirmed: true) }

  def confirm!
    update!(confirmed: true)
  end

  def unconfirm!
    update!(confirmed: false)
  end

  # Cantidad entregada hasta ahora
  def delivered_quantity
    delivery_items.delivered.sum(:quantity_delivered)
  end

  # Cantidad pendiente de entrega
  def pending_quantity
    quantity - delivered_quantity
  end

  # Verifica si está completamente entregado
  def fully_delivered?
    delivered_quantity >= quantity
  end

  # Marca como entregado si está completo
  def check_delivery_status!
    if fully_delivered?
      update!(status: :delivered)
      order.check_and_update_status! if order.fully_delivered?
    end
  end
end