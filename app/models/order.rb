# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :client
  belongs_to :seller
  has_many :order_items, dependent: :destroy
  has_many :deliveries, dependent: :destroy

  validates :number, presence: true, uniqueness: true

  enum status: { pending: 0, in_production: 1, ready_for_delivery: 2, delivered: 3, rescheduled: 4, cancelled: 5 }

  # Verifica si está completamente entregado
  def fully_delivered?
    order_items.all?(&:fully_delivered?)
  end

  # Actualiza el estado basado en los order_items
  def check_and_update_status!
    if order_items.all? { |item| item.status == "delivered" }
      update!(status: :delivered)
    elsif order_items.all? { |item| item.status == "cancelled" }
      update!(status: :cancelled)
    elsif order_items.any? { |item| item.status == "rescheduled" }
      update!(status: :rescheduled)
    elsif order_items.all? { |item| ["ready", "delivered"].include?(item.status) }
      update!(status: :ready_for_delivery)
    elsif order_items.any? { |item| item.status == "ready" }
      update!(status: :in_production)
    else
      update!(status: :pending)
    end
  end

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

  def self.ransackable_attributes(auth_object = nil)
    ["client_id", "number", "seller_id", "status", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["client", "seller", "order_items", "deliveries"]
  end
end