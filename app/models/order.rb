# app/models/order.rb
class Order < ApplicationRecord
  has_paper_trail
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

  # Total de items en el pedido
  def total_items
    order_items.sum(:quantity)
  end

  def pending_items
    order_items.where.not(status: :delivered)
  end

  # Métodos de conveniencia para casos de servicio
  def has_service_deliveries?
    deliveries.service_cases.any?
  end

  def service_delivery_types
    deliveries.service_cases.pluck(:delivery_type).uniq
  end

  # Método para crear deliveries de servicio
  def create_service_deliveries(pickup: false, return_delivery: false, onsite_repair: false, delivery_date: Date.current, contact_name: nil, contact_phone: nil, delivery_address_id: nil)
    delivery_params = {
      delivery_date: delivery_date,
      contact_name: contact_name,
      contact_phone: contact_phone,
      delivery_address_id: delivery_address_id,
      status: :ready_to_deliver
    }

    created_deliveries = []

    if pickup
      created_deliveries << deliveries.create!(delivery_params.merge(delivery_type: :pickup))
    end

    if return_delivery
      created_deliveries << deliveries.create!(delivery_params.merge(delivery_type: :return_delivery))
    end

    if onsite_repair
      created_deliveries << deliveries.create!(delivery_params.merge(delivery_type: :onsite_repair))
    end

    created_deliveries
  end

  def self.ransackable_attributes(auth_object = nil)
    ["client_id", "number", "seller_id", "status", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["client", "seller", "order_items", "deliveries"]
  end
end