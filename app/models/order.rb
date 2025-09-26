# app/models/order.rb
class Order < ApplicationRecord
  # ============================================================================
  # CONFIGURACIÓN Y RELACIONES
  # ============================================================================

  has_paper_trail
  belongs_to :client
  belongs_to :seller
  has_many :order_items, dependent: :destroy
  has_many :deliveries, dependent: :destroy
  has_many :order_item_notes, through: :order_items

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
      .where(deliveries: { delivery_date: start_date..end_date })
      .distinct
  }

  # Filtrar por vendedor
  scope :by_seller, ->(seller) { where(seller: seller) }

  # Filtrar por código de vendedor
  scope :by_seller_code, ->(code) { joins(:seller).where(sellers: { seller_code: code }) }

  # Pedidos activos
  scope :active, -> { where(status: [ :pending, :in_production, :ready_for_delivery, :rescheduled ]) }

  scope :in_production, -> { where(status: :in_production) }

  scope :notes_status_with, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM order_item_notes
        JOIN order_items ON order_items.id = order_item_notes.order_item_id
        WHERE order_items.order_id = orders.id
      )"
    )
  }

  scope :notes_status_open, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM order_item_notes
        JOIN order_items ON order_items.id = order_item_notes.order_item_id
        WHERE order_items.order_id = orders.id
        AND order_item_notes.closed = 0
      )"
    )
  }

  scope :notes_status_closed, -> {
    where(
      "EXISTS (
        SELECT 1
        FROM order_item_notes
        JOIN order_items ON order_items.id = order_item_notes.order_item_id
        WHERE order_items.order_id = orders.id
        AND order_item_notes.closed = 1
      )"
    )
  }

  # ============================================================================
  # MÉTODOS DE ESTADO Y UTILIDAD
  # ============================================================================

  def display_status
    case status
    when "in_production"     then "En producción"
    when "ready_for_delivery" then "Listo para entrega"
    when "delivered"         then "Entregado"
    when "rescheduled"       then "Reprogramado"
    when "cancelled"         then "Cancelado"
    else status.to_s.humanize
    end
  end

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
                                          .where.not(deliveries: { status: [ :rescheduled, :archived ] })

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

  # Método de clase para corregir TODAS las órdenes
  def self.fix_all_order_item_quantities!
    corrected_count = 0
    error_count = 0

    Order.includes(:order_items).find_each do |order|
      begin
        order.fix_order_item_quantities!
        corrected_count += 1
        print "." # Progreso visual
      rescue => e
        Rails.logger.error "Error corrigiendo Order #{order.number}: #{e.message}"
        error_count += 1
        print "X"
      end
    end
  end

  # Método para obtener un reporte de diferencias SIN corregir
  def self.audit_order_item_quantities
    discrepancies = []

    Order.includes(:order_items).find_each do |order|
      order.order_items.each do |order_item|
        valid_delivery_items = DeliveryItem.joins(:delivery)
                                          .where(order_item: order_item)
                                          .where.not(deliveries: { status: :rescheduled })

        total_delivered = valid_delivery_items.sum(:quantity_delivered)

        if order_item.quantity != total_delivered
          discrepancies << {
            order_number: order.number,
            product: order_item.product,
            current_quantity: order_item.quantity,
            should_be_quantity: total_delivered,
            difference: total_delivered - order_item.quantity
          }
        end
      end
    end

    discrepancies
  end

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
            FROM order_item_notes
            JOIN order_items ON order_items.id = order_item_notes.order_item_id
            WHERE order_items.order_id = orders.id
          )
        SQL
      when "open"
        Arel.sql <<-SQL
          EXISTS (
            SELECT 1
            FROM order_item_notes
            JOIN order_items ON order_items.id = order_item_notes.order_item_id
            WHERE order_items.order_id = orders.id
            AND order_item_notes.closed = 0
          )
        SQL
      when "closed"
        Arel.sql <<-SQL
          EXISTS (
            SELECT 1
            FROM order_item_notes
            JOIN order_items ON order_items.id = order_item_notes.order_item_id
            WHERE order_items.order_id = orders.id
            AND order_item_notes.closed = 1
          )
        SQL
      else
        nil
      end
    } do |_parent|
    Arel.sql("TRUE") # dummy, solo para que ransack lo acepte
  end

  def self.ransackable_attributes(_ = nil)
    %w[client_id number seller_id status created_at updated_at notes_status]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "client", "seller", "order_items", "deliveries", "order_item_notes" ]
  end

  def self.human_enum_name(enum_name, value)
    I18n.t("activerecord.attributes.#{model_name.i18n_key}.#{enum_name.to_s.pluralize}.#{value}")
  end

  # ============================================================================
  # CALLBACKS PRIVADOS
  # ============================================================================

  private

  # Notifica cuando cambia el estado del pedido
  def notify_status_change
    case status
    when "ready_for_delivery"
      NotificationService.notify_order_ready_for_delivery(self)
    end
  end

  # Setea el estado por defecto al crear un pedido
  def set_default_status
    self.status ||= :in_production
  end

  def self.status_options_for_select
    statuses.keys.map do |s|
      [ Order.new(status: s).display_status, s ]
    end
  end
end
