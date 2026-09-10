# app/models/order.rb

# Pedido de un cliente, tomado por un vendedor (seller). Un Order agrupa
# {OrderItem}s (los productos pedidos) y se entrega mediante una o varias
# {Delivery}s. El status de un Order es derivado: se recalcula automáticamente
# en {#check_and_update_status!} cada vez que cambia el status de alguno de
# sus order_items (ver {OrderItem#update_status_based_on_deliveries}).
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
  scope :active, -> { where(status: [:in_production, :ready_for_delivery, :rescheduled]) }

  scope :in_production, -> { where(status: :in_production) }

  scope :notes_status_with, -> { where(notes_status_exists_sql(nil)) }
  scope :notes_status_open, -> { where(notes_status_exists_sql(false)) }
  scope :notes_status_closed, -> { where(notes_status_exists_sql(true)) }

  # ============================================================================
  # MÉTODOS DE ESTADO Y UTILIDAD
  # ============================================================================


  # Recalcula y persiste el status del pedido en base al status agregado de
  # sus order_items. Se llama automáticamente desde
  # {OrderItem#update_order_status} cada vez que un order_item cambia; no
  # suele hacer falta invocarlo a mano salvo para corregir datos.
  #
  # @return [void]
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

  # Corrige `quantity` de cada order_item para que coincida con la suma real
  # de `quantity_delivered` entre sus delivery_items (excluyendo los de
  # deliveries rescheduled/archived). Método de reparación de datos, no se
  # llama en el flujo normal.
  #
  # @return [void]
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

  # Reasigna el pedido a otro vendedor.
  #
  # @param seller [Seller]
  # @return [void]
  def reassign_to_seller!(seller)
    update!(seller: seller)
  end

  # Reasigna el pedido al vendedor asociado a un usuario.
  #
  # @param user [User] debe tener un {Seller} asociado (`user.seller`)
  # @raise [RuntimeError] si el usuario no tiene vendedor asociado
  # @return [void]
  def take_by_user!(user)
    seller_record = user.seller
    raise "El usuario no tiene vendedor asociado" unless seller_record

    update!(seller: seller_record)
  end

  # @return [Boolean] true si todos los order_items están en status "ready"
  def all_items_ready?
    order_items.all? { |item| item.ready? }
  end

  # @return [Integer] suma de `quantity` de todos los order_items del pedido
  def total_items
    order_items.sum(:quantity)
  end

  # ============================================================================
  # RANSACK
  # ============================================================================

  # SQL compartido por los scopes notes_status_* y el ransacker notes_status.
  #
  # @param closed [Boolean, nil] nil => sin filtrar por closed (cualquier
  #   nota), false => solo notas abiertas, true => solo notas cerradas
  # @return [Arel::Nodes::SqlLiteral] fragmento `EXISTS (...)` listo para `where`
  def self.notes_status_exists_sql(closed)
    closed_clause = closed.nil? ? "" : "AND delivery_item_notes.closed = #{closed ? 1 : 0}"
    Arel.sql <<-SQL
      EXISTS (
        SELECT 1
        FROM delivery_item_notes
        JOIN delivery_items ON delivery_items.id = delivery_item_notes.delivery_item_id
        JOIN order_items ON order_items.id = delivery_items.order_item_id
        WHERE order_items.order_id = orders.id
        #{closed_clause}
      )
    SQL
  end

  ransacker :notes_status,
    formatter: proc { |value|
      case value.to_s
      when "with" then notes_status_exists_sql(nil)
      when "open" then notes_status_exists_sql(false)
      when "closed" then notes_status_exists_sql(true)
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

  # @return [Array<Array(String, String)>] pares [etiqueta legible, valor de
  #   enum] para poblar un `<select>` de status
  def self.status_options_for_select
    statuses.keys.map do |s|
      [Order.new(status: s).display_status, s]
    end
  end

  # ============================================================================
  # CALLBACKS PRIVADOS
  # ============================================================================

  private

  # Hook para notificar cuando cambia el estado del pedido.
  #
  # @note actualmente es un no-op: la única rama (ready_for_delivery) tiene
  #   la llamada al servicio de notificación comentada.
  # @return [void]
  def notify_status_change
    case status
    when "ready_for_delivery"
      # NotificationService.notify_order_ready_for_delivery(self)
    end
  end

  # @return [void]
  def set_default_status
    self.status ||= :in_production
  end
end
