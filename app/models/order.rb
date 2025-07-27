# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :client
  belongs_to :seller
  has_many :order_items, dependent: :destroy
  has_many :deliveries, dependent: :destroy

  enum status: { pending: 0, in_production: 1, ready_for_delivery: 2, delivered: 3, rescheduled: 4, cancelled: 5 }

  validates :number, presence: true, uniqueness: true

  # Scope para filtrar pedidos listos para entrega en una semana específica
  scope :ready_for_week, ->(start_date, end_date) {
    joins(:deliveries)
      .where(status: :ready_for_delivery)
      .where(deliveries: { delivery_date: start_date..end_date })
      .distinct
  }

  # Scope para filtrar por vendedor
  scope :by_seller, ->(seller) { where(seller: seller) }

  # Scope para filtrar por codigo de vendedor
  scope :by_seller_code, ->(code) { joins(:seller).where(sellers: { seller_code: code }) }

  # Verifica si todos los items están listos
  def all_items_ready?
    order_items.all? { |item| item.ready? }
  end

  # Marca el pedido como listo si todos los items están listos
  def check_and_update_status!
    if all_items_ready? && in_production?
      update!(status: :ready_for_delivery)
    end
  end

  # Total de items en el pedido
  def total_items
    order_items.sum(:quantity)
  end

  def pending_items
    order_items.where.not(status: :delivered)
  end

  def fully_delivered?
    order_items.all?(&:fully_delivered?)
  end
end