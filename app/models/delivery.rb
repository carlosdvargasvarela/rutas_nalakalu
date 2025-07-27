# app/models/delivery.rb
class Delivery < ApplicationRecord
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items

  enum status: { scheduled: 0, in_route: 1, delivered: 2, rescheduled: 3, cancelled: 4 }

  validates :delivery_date, presence: true
  validates :contact_name, presence: true

  after_save :update_status_based_on_items

  def update_status_based_on_items
    statuses = delivery_items.pluck(:status)

    if statuses.all? { |s| s == "delivered" }
      update_column(:status, Delivery.statuses[:delivered])
    elsif statuses.all? { |s| s == "cancelled" }
      update_column(:status, Delivery.statuses[:cancelled])
    elsif statuses.any? { |s| s == "rescheduled" } && statuses.none? { |s| ["pending", "ready"].include?(s) }
      update_column(:status, Delivery.statuses[:rescheduled])
    elsif statuses.any? { |s| s == "in_route" }
      update_column(:status, Delivery.statuses[:in_route])
    elsif statuses.all? { |s| ["pending", "ready"].include?(s) }
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
    ]
  end

  # Si quieres permitir búsquedas por asociaciones (por ejemplo, cliente del pedido):
  def self.ransackable_associations(auth_object = nil)
    ["order", "delivery_address", "delivery_items"]
  end

end