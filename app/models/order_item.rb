# app/models/order_item.rb
class OrderItem < ApplicationRecord
  has_paper_trail

  # Relaciones
  belongs_to :order
  has_many :delivery_items, dependent: :destroy
  has_many :order_item_notes, dependent: :destroy

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
  after_update :update_order_status
  after_update :notify_ready, if: :saved_change_to_status?

  def display_status
    case status
    when "in_production" then "En producción"
    when "ready"         then "Listo"
    when "delivered"     then "Entregado"
    when "cancelled"     then "Cancelado"
    when "missing"       then "Faltante"
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

  private

  def notify_ready
    if status == "ready"
      # Marcar el último delivery_item como confirmado si existe
      puts "Notificando que el producto '#{product}' del pedido #{order.number} está listo para confirmar con el cliente."
      seller_user = order.seller.user
      message = "El producto '#{product}' del pedido #{order.number} está listo para confirmar con el cliente."
      NotificationService.create_for_users([seller_user], self, message)
    end
  end
end
