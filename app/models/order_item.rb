# app/models/order_item.rb
class OrderItem < ApplicationRecord
  has_paper_trail

  # Relaciones
  belongs_to :order
  has_many :delivery_items, dependent: :destroy
  has_many :order_item_notes, dependent: :destroy

  validates :product, presence: true
  validates :product, uniqueness: {scope: :order_id, message: "ya existe en este pedido"}
  validates :quantity, presence: true, numericality: {greater_than: 0}

  # Scopes
  scope :to_be_confirmed, -> { where(confirmed: [nil, false]) }
  scope :confirmed, -> { where(confirmed: true) }

  # Enum para el estado del order_item
  enum status: {
    in_production: 0,   # Default
    ready: 1,
    delivered: 2,
    cancelled: 3,
    missing: 4
  }

  # Callbacks
  after_save :update_status_based_on_deliveries
  after_update :update_order_status

  # ✅ MÉTODOS DE AYUDA PARA CLARIDAD (Capa 2)
  def delivered_quantity
    delivery_items.sum(:quantity_delivered)
  end

  def pending_quantity
    quantity - delivered_quantity
  end

  def notes_open?
    order_item_notes.open.exists?
  end

  def display_status
    case status
    when "in_production" then "En producción"
    when "ready" then "Listo"
    when "delivered" then "Entregado"
    when "cancelled" then "Cancelado"
    when "missing" then "Faltante"
    else status.to_s.humanize
    end
  end

  def update_status_based_on_deliveries
    if delivery_items.any? && delivery_items.all? { |di| di.status == "delivered" }
      update_column(:status, OrderItem.statuses[:delivered])
    elsif status != "cancelled" && ready_to_deliver?
      update_column(:status, OrderItem.statuses[:ready])
    end
    update_order_status
  end

  def update_order_status
    order.check_and_update_status! if order.present?
  end

  def confirm!
    order_item_notes.each do |note|
      note.update(closed: true) unless note.closed?
    end
    update!(confirmed: true, status: :ready)
  end

  def unconfirm!
    update!(confirmed: false, status: :in_production)
  end

  def ready_to_deliver?
    status == "ready"
  end

  def item_delivery_status
    delivery_items.last.status
  end

  def self.ransackable_associations(auth_object = nil)
    ["order", "delivery_items", "order_item_notes"]
  end

  def self.ransackable_attributes(auth_object = nil)
    ["product", "quantity", "status", "confirmed", "created_at", "updated_at"]
  end
end
