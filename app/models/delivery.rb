# app/models/delivery.rb
class Delivery < ApplicationRecord
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items

  enum status: { scheduled: 0, in_route: 1, delivered: 2, rescheduled: 3, cancelled: 4 }

  validates :delivery_date, presence: true
  validates :contact_name, presence: true

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
end