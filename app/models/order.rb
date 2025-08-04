# app/models/order.rb
class Order < ApplicationRecord
  has_paper_trail
  belongs_to :client
  belongs_to :seller
  has_many :order_items, dependent: :destroy
  has_many :deliveries, dependent: :destroy

  validates :number, presence: true, uniqueness: true

  after_update :notify_status_change, if: :saved_change_to_status?

  enum status: {
    in_production: 0,   # Default
    ready_for_delivery: 1,
    delivered: 2,
    rescheduled: 3,
    cancelled: 4
  }

  # Actualiza el estado basado en los order_items
  def check_and_update_status!
    return if order_items.empty?

    statuses = order_items.pluck(:status)

    if statuses.all? { |s| s == "delivered" }
      update!(status: :delivered)
    elsif statuses.all? { |s| s == "cancelled" }
      update!(status: :cancelled)
    elsif statuses.all? { |s| [ "ready", "delivered" ].include?(s) }
      update!(status: :ready_for_delivery)
    elsif statuses.all? { |s| s == "rescheduled" }
      update!(status: :rescheduled)
    elsif statuses.any? { |s| [ "in_production", "missing" ].include?(s) }
      update!(status: :in_production)
    else
      # Default fallback
      update!(status: :in_production)
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

  scope :active, -> { where(status: [ :pending, :in_production, :ready_for_delivery, :rescheduled ]) }

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
    [ "client_id", "number", "seller_id", "status", "created_at", "updated_at" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "client", "seller", "order_items", "deliveries" ]
  end

  private

  def notify_status_change
    case status
    when "ready_for_delivery"
      NotificationService.notify_order_ready_for_delivery(self)
    end
  end
end
