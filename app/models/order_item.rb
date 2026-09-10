# app/models/order_item.rb

# Un producto dentro de un {Order}. Se entrega a través de uno o más
# {DeliveryItem} (una entrega parcial o reprogramación genera otro
# DeliveryItem apuntando al mismo OrderItem). El status del OrderItem se
# recalcula solo, en {#update_status_based_on_deliveries}, a partir del
# status de sus delivery_items — no se setea a mano salvo en {#confirm!} /
# {#unconfirm!}.
class OrderItem < ApplicationRecord
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "in_production" => "En producción",
    "ready" => "Listo",
    "delivered" => "Entregado",
    "cancelled" => "Cancelado",
    "missing" => "Faltante"
  }.freeze

  has_paper_trail

  # Relaciones
  belongs_to :order
  has_many :delivery_items, dependent: :destroy
  has_many :delivery_item_notes, through: :delivery_items

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
  # update_status_based_on_deliveries ya llama update_order_status al final,
  # así que no hace falta un after_update separado (duplicaría el recálculo
  # del Order en cada update).
  after_save :update_status_based_on_deliveries

  # @return [Integer] suma de `quantity_delivered` entre todos los delivery_items
  def delivered_quantity
    delivery_items.sum(:quantity_delivered)
  end

  # Recalcula el status del order_item a partir del status de sus
  # delivery_items: "delivered" si todos fueron entregados, "ready" si ya
  # estaba confirmado como listo (y no cancelado). Se ejecuta después de
  # cada save (propio o vía callback de un DeliveryItem hijo) y en cascada
  # dispara {#update_order_status}.
  #
  # @note usa `update_column` (sin validaciones ni callbacks) para evitar
  #   recursión infinita entre este callback y el de guardado.
  # @return [void]
  def update_status_based_on_deliveries
    if delivery_items.any? && delivery_items.all? { |di| di.status == "delivered" }
      update_column(:status, OrderItem.statuses[:delivered])
    elsif status != "cancelled" && ready_to_deliver?
      update_column(:status, OrderItem.statuses[:ready])
    end
    update_order_status
  end

  # Propaga el recálculo de status hacia arriba, al Order dueño.
  #
  # @return [void]
  def update_order_status
    order.check_and_update_status! if order.present?
  end

  # Marca el order_item como confirmado y listo para entrega, cerrando
  # cualquier nota pendiente sobre sus delivery_items.
  #
  # @return [void]
  def confirm!
    delivery_item_notes.each do |note|
      note.update(closed: true) unless note.closed?
    end
    update!(confirmed: true, status: :ready)
  end

  # Revierte una confirmación: vuelve a "in_production" y desmarca confirmed.
  #
  # @return [void]
  def unconfirm!
    update!(confirmed: false, status: :in_production)
  end

  # @return [Boolean] true si el status actual es "ready"
  def ready_to_deliver?
    status == "ready"
  end

  # @return [String] nombre del producto (alias de {#product})
  def product_name
    product
  end

  def self.ransackable_associations(auth_object = nil)
    ["order", "delivery_items", "delivery_item_notes"]
  end

  def self.ransackable_attributes(auth_object = nil)
    ["product", "quantity", "status", "confirmed", "created_at", "updated_at"]
  end
end
