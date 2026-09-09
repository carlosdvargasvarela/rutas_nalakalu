# app/models/order.rb
class Order < ApplicationRecord
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "in_production" => "En producción",
    "ready_for_delivery" => "Listo para entrega",
    "delivered" => "Entregado",
    "rescheduled" => "Reprogramado",
    "cancelled" => "Cancelado"
  }.freeze

  # ============================================================================
  # CONFIGURACIÓN Y RELACIONES
  # ============================================================================

  has_paper_trail
  belongs_to :client
  belongs_to :seller
  has_many :order_items, dependent: :destroy
  has_many :deliveries, dependent: :destroy
  has_many :delivery_item_notes, through: :order_items
  has_many :order_contacts, dependent: :destroy

  # ============================================================================
  # VALIDACIONES
  # ============================================================================

  validates :number, presence: true

  # ============================================================================
  # ENUMS
  # ============================================================================

  enum status: {
    in_production: 0,   # Default
    ready_for_delivery: 1,
    delivered: 2,
    rescheduled: 3,
    cancelled: 4
  }

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  after_initialize :set_default_status, if: :new_record?
  after_update :notify_status_change, if: :saved_change_to_status?

  # ============================================================================
  # SCOPES
  # ============================================================================

  # Pedidos listos para entrega en una semana específica
  scope :ready_for_week, ->(start_date, end_date) {
    joins(:deliveries)
      .where(status: :ready_for_delivery)
      .where(deliveries: {delivery_date: start_date..end_date})
      .distinct
  }

  # Filtrar por vendedor
  scope :by_seller, ->(seller) { where(seller: seller) }

  # Filtrar por código de vendedor
  scope :by_seller_code, ->(code) { joins(:seller).where(sellers: {seller_code: code}) }

  # Pedidos activos
  scope :active, -> { where(status: [:pending, :in_production, :ready_for_delivery, :rescheduled]) }

  scope :in_production, -> { where(status: :in_production) }

  scope :notes_status_with, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM delivery_item_notes
        JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
        JOIN order_items ON order_items.id = delivery_items.order_item_id
        WHERE order_items.order_id = orders.id
      )"
    )
  }

  scope :notes_status_open, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM delivery_item_notes
        JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
        JOIN order_items ON order_items.id = delivery_items.order_item_id
        WHERE order_items.order_id = orders.id
        AND delivery_item_notes.closed = 0
      )"
    )
  }

  scope :notes_status_closed, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM delivery_item_notes
        JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
        JOIN order_items ON order_items.id = delivery_items.order_item_id
        WHERE order_items.order_id = orders.id
        AND delivery_item_notes.closed = 1
      )"
    )
  }

  # ============================================================================
  # MÉTODOS DE ESTADO Y UTILIDAD
  # ============================================================================


  # Actualiza el estado basado en los order_items
  def check_and_update_status!
    return if order_items.empty?

    statuses = order_items.pluck(:status)

    if statuses.all? { |s| s == "delivered" }
      update!(status: :delivered)
    elsif statuses.all? { |s| s == "cancelled" }
      update!(status: :cancelled)
    elsif statuses.all? { |s| ["ready", "delivered"].include?(s) }
      update!(status: :ready_for_delivery)
    elsif statuses.all? { |s| s == "rescheduled" }
      update!(status: :rescheduled)
    elsif statuses.any? { |s| ["in_production", "missing"].include?(s) }
      update!(status: :in_production)
    else
      update!(status: :in_production)
    end
  end

  # Método para corregir las cantidades de order_items basándose en deliveries reales
  def fix_order_item_quantities!
    transaction do
      order_items.each do |order_item|
        # Obtener todos los delivery_items de este order_item
        # excluyendo los que pertenecen a deliveries rescheduled
        valid_delivery_items = DeliveryItem.joins(:delivery)
          .where(order_item: order_item)
          .where.not(deliveries: {status: [:rescheduled, :archived]})

        # Sumar todas las cantidades entregadas reales
        total_delivered_quantity = valid_delivery_items.sum(:quantity_delivered)

        # Solo actualizar si hay diferencia
        if order_item.quantity != total_delivered_quantity
          Rails.logger.info "Order #{number} - #{order_item.product}: #{order_item.quantity} → #{total_delivered_quantity}"
          order_item.update!(quantity: total_delivered_quantity)
        end
      end
    end
  end

  def reassign_to_seller!(seller)
    update!(seller: seller)
  end

  def take_by_user!(user)
    seller_record = user.seller
    raise "El usuario no tiene vendedor asociado" unless seller_record

    update!(seller: seller_record)
  end

  # Verifica si todos los items están listos
  def all_items_ready?
    order_items.all? { |item| item.ready? }
  end

  # Total de items en el pedido
  def total_items
    order_items.sum(:quantity)
  end

  # ============================================================================
  # RANSACK
  # ============================================================================

  ransacker :notes_status,
    formatter: proc { |value|
      case value.to_s
      when "with"
        Arel.sql <<-SQL
          EXISTS (
            SELECT 1
            FROM delivery_item_notes
            JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
            JOIN order_items ON order_items.id = delivery_items.order_item_id
            WHERE order_items.order_id = orders.id
          )
        SQL
      when "open"
        Arel.sql <<-SQL
          EXISTS (
            SELECT 1
            FROM delivery_item_notes
            JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
            JOIN order_items ON order_items.id = delivery_items.order_item_id
            WHERE order_items.order_id = orders.id
            AND delivery_item_notes.closed = 0
          )
        SQL
      when "closed"
        Arel.sql <<-SQL
          EXISTS (
            SELECT 1
            FROM delivery_item_notes
            JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
            JOIN order_items ON order_items.id = delivery_items.order_item_id
            WHERE order_items.order_id = orders.id
            AND delivery_item_notes.closed = 1
          )
        SQL
      end
    } do |_parent|
    Arel.sql("TRUE") # dummy, solo para que ransack lo acepte
  end

  def self.ransackable_attributes(_ = nil)
    %w[client_id number seller_id status created_at updated_at notes_status]
  end

  def self.ransackable_associations(auth_object = nil)
    ["client", "seller", "order_items", "deliveries", "delivery_item_notes"]
  end

  def self.status_options_for_select
    statuses.keys.map do |s|
      [Order.new(status: s).display_status, s]
    end
  end

  # ============================================================================
  # CALLBACKS PRIVADOS
  # ============================================================================

  private

  # Notifica cuando cambia el estado del pedido
  def notify_status_change
    case status
    when "ready_for_delivery"
      # NotificationService.notify_order_ready_for_delivery(self)
    end
  end

  # Setea el estado por defecto al crear un pedido
  def set_default_status
    self.status ||= :in_production
  end
end
