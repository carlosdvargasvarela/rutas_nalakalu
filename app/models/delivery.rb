# app/models/delivery.rb
class Delivery < ApplicationRecord
  has_paper_trail
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items

  accepts_nested_attributes_for :delivery_items, allow_destroy: true

  enum status: { scheduled: 0, in_route: 1, delivered: 2, rescheduled: 3, cancelled: 4, ready_to_deliver: 5 }
  enum delivery_type: { normal_delivery: 0, service_case: 1 }

  validates :delivery_date, presence: true
  validates :contact_name, presence: true

  after_save :update_status_based_on_items

  # Nuevos tipos de delivery
  enum delivery_type: {
    normal: 0,           # Entrega normal de productos
    pickup: 1,           # Recogida de producto en casa del cliente
    return_delivery: 2,  # Devolución de producto reparado
    onsite_repair: 3     # Reparación en sitio del cliente
  }

  # Scopes útiles
  scope :service_cases, -> { where(delivery_type: [ :pickup, :return_delivery, :onsite_repair ]) }
  scope :normal_deliveries, -> { where(delivery_type: :normal) }
  scope :pending, -> { where(status: [ :scheduled, :ready_to_deliver, :in_route ]) }

  # Métodos de conveniencia
  def service_case?
    pickup? || return_delivery? || onsite_repair?
  end

  def display_type
    case delivery_type
    when "normal" then "Entrega normal"
    when "pickup" then "Recogida de producto"
    when "return_delivery" then "Devolución de producto"
    when "onsite_repair" then "Reparación en sitio"
    end
  end

  # Ransack (para filtros)
  def self.ransackable_attributes(auth_object = nil)
    %w[delivery_date status delivery_type contact_name contact_phone delivery_notes delivery_time_preference]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[order delivery_address delivery_items]
  end

  def update_status_based_on_items
    statuses = delivery_items.pluck(:status)

    # Todos entregados o reagendados
    if statuses.all? { |s| [ "delivered", "rescheduled" ].include?(s) }
      update_column(:status, Delivery.statuses[:delivered])
    elsif statuses.all? { |s| [ "confirmed", "rescheduled" ].include?(s) }
      update_column(:status, Delivery.statuses[:ready_to_deliver])
    elsif statuses.all? { |s| s == "cancelled" }
      update_column(:status, Delivery.statuses[:cancelled])
    elsif statuses.any? { |s| s == "rescheduled" } && statuses.none? { |s| [ "pending", "ready", "confirmed", "in_route" ].include?(s) }
      update_column(:status, Delivery.statuses[:rescheduled])
    elsif statuses.any? { |s| s == "in_route" }
      update_column(:status, Delivery.statuses[:in_route])
    elsif statuses.all? { |s| [ "pending", "ready", "confirmed" ].include?(s) }
      update_column(:status, Delivery.statuses[:scheduled])
    else
      update_column(:status, Delivery.statuses[:scheduled])
    end
  end

  # Scope para entregas de una semana específica
  scope :for_week, ->(date) {
    week = date.cweek
    year = date.cwyear
    where("EXTRACT(week FROM delivery_date) = ? AND EXTRACT(year FROM delivery_date) = ?", week, year)
  }
  # Scope para casos de servicio
  scope :with_service_cases, -> {
    joins(:delivery_items).where(delivery_items: { service_case: true }).distinct
  }

  # Scope para entregas normales
  scope :normal_deliveries, -> {
    joins(:delivery_items).where(delivery_items: { service_case: false }).distinct
  }

  # Verifica si tiene casos de servicio
  def has_service_cases?
    delivery_items.any?(&:service_case?)
  end

  # Total de items en esta entrega
  def total_items
    delivery_items.sum(:quantity_delivered)
  end

  # Marca la entrega como completada
  def mark_as_delivered!
    transaction do
      update!(status: :delivered)
      delivery_items.each(&:mark_as_delivered!)
    end
  end

  # Información del cliente para logística
  def client_info
    {
      name: order.client.name,
      address: delivery_address.address,
      contact: contact_name,
      phone: contact_phone,
      seller: order.seller.name
    }
  end

  def self.ransackable_attributes(auth_object = nil)
    [
      "contact_id",
      "contact_name",
      "contact_phone",
      "created_at",
      "delivery_address_id",
      "delivery_date",
      "delivery_notes",
      "delivery_time_preference",
      "id",
      "order_id",
      "status",
      "updated_at"
    ] + _ransackers.keys
  end

  def self.ransackable_associations(auth_object = nil)
    [ "order", "delivery_address", "delivery_items" ]
  end
end
