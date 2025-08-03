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
  enum status: {
    in_production: 0,   # Default
    ready: 1,
    delivered: 2,
    cancelled: 3,
    missing: 4
  }

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
end
