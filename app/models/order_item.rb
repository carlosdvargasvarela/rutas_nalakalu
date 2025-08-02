# app/models/order_item.rb
class OrderItem < ApplicationRecord
  has_paper_trail

  # Relaciones
  belongs_to :order
  has_many :delivery_items, dependent: :destroy

  # Validaciones
  validates :product, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :to_be_confirmed, -> { where(confirmed: [ nil, false ]) }
  scope :confirmed, -> { where(confirmed: true) }

  # Enum para el estado del order_item
  enum status: { pending: 0, ready: 1, delivered: 2, cancelled: 3, missing_or_incomplete: 4 }

  # Callback para actualizar el estado del order_item basado en las entregas
  after_save :update_status_based_on_deliveries

  def update_status_based_on_deliveries
    if delivery_items.any? && delivery_items.all? { |di| di.status == "delivered" }
      update_column(:status, OrderItem.statuses[:delivered])
    elsif status != "cancelled" && ready_to_deliver?
      update_column(:status, OrderItem.statuses[:ready])
    end
  end

  def confirm!
    update!(confirmed: true, status: :ready)
  end

  def ready_to_deliver?
    status == "ready"
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
      order.update_status_based_on_items
    end
  end
end
