# app/models/delivery.rb
class Delivery < ApplicationRecord
  has_paper_trail
  belongs_to :order
  belongs_to :delivery_address
  has_many :delivery_items, dependent: :destroy
  has_many :order_items, through: :delivery_items
  has_many :delivery_plan_assignments, dependent: :destroy
  has_many :delivery_plans, through: :delivery_plan_assignments

  accepts_nested_attributes_for :delivery_items, allow_destroy: true

  enum status: {
    scheduled: 0,
    ready_to_deliver: 1,
    in_plan: 2,
    in_route: 3,
    delivered: 4,
    rescheduled: 5,
    cancelled: 6
  }

  validates :delivery_date, presence: true

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
  scope :overdue, -> {
  where("delivery_date < ?", Date.current)
    .where.not(status: [ Delivery.statuses[:delivered],
                         Delivery.statuses[:rescheduled],
                         Delivery.statuses[:cancelled] ])}
  scope :eligible_for_plan, -> { where(status: [ :scheduled, :ready_to_deliver ]) }
  scope :not_assigned_to_plan, -> { where.not(id: DeliveryPlanAssignment.select(:delivery_id)) }
  scope :available_for_plan, -> { eligible_for_plan.not_assigned_to_plan }

  # Métodos de conveniencia
  def service_case?
    pickup? || return_delivery? || onsite_repair?
  end

  def display_status
    case status
    when "scheduled"        then "Pendiente de confirmar"
    when "ready_to_deliver" then "Confirmada para entregar"
    when "in_plan"          then "En plan"
    when "in_route"         then "En ruta"
    when "delivered"        then "Entregada"
    when "rescheduled"      then "Reprogramada"
    when "cancelled"        then "Cancelada"
    else status.to_s.humanize
    end
  end

  def display_type
    case delivery_type
    when "normal"         then "Entrega normal"
    when "pickup"         then "Recogida de producto"
    when "return_delivery" then "Devolución de producto"
    when "onsite_repair"  then "Reparación en sitio"
    else delivery_type.to_s.humanize
    end
  end

  # Ransack (para filtros)
  def self.ransackable_attributes(auth_object = nil)
    %w[delivery_date status delivery_type contact_name contact_phone delivery_notes delivery_time_preference]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[order delivery_address delivery_items]
  end

  # Actualiza el estado de la entrega basado en los items
  def update_status_based_on_items
    statuses = delivery_items.pluck(:status)
    return if statuses.empty?

    if statuses.all? { |s| s == "delivered" }
      update_column(:status, Delivery.statuses[:delivered])
    elsif statuses.all? { |s| s == "cancelled" }
      update_column(:status, Delivery.statuses[:cancelled])
    elsif statuses.all? { |s| s == "rescheduled" }
      update_column(:status, Delivery.statuses[:rescheduled])
    elsif statuses.all? { |s| [ "rescheduled", "confirmed" ].include?(s) }
      update_column(:status, Delivery.statuses[:ready_to_deliver])
    elsif statuses.any? { |s| s == "in_route" }
      update_column(:status, Delivery.statuses[:in_route])
    elsif statuses.all? { |s| [ "pending", "confirmed" ].include?(s) }
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
      delivery_items.each(&:mark_as_delivered!)
      update!(status: :delivered)
    end
  end

  def confirmed?
    order_items.all? { |oi| oi.status == "ready" }
  end

  def delivery_plan
    delivery_plans.first
  end

  def delivery_history
    order.deliveries
        .where(delivery_address_id: delivery_address_id)
        .includes(delivery_items: :order_item) # <- cargar productos en bloque
        .order(:delivery_date)
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

  def status_humanize
    status.humanize
  end

  def delivery_type_humanize
    delivery_type.humanize
  end

  def self.to_csv
      CSV.generate(headers: true) do |csv|
        csv << [ "Fecha de entrega", "Pedido", "Producto", "Cantidad", "Vendedor", "Cliente", "Dirección", "Estado", "Tipo" ]
        all.includes(order: [ :client, :seller ], delivery_address: :client, delivery_items: { order_item: :order }).find_each do |delivery|
          delivery.delivery_items.each do |delivery_item|
            csv << [
              delivery.delivery_date.strftime("%d/%m/%Y"),
              delivery.order.number,
              delivery_item.order_item.product,
              delivery_item.order_item.quantity,
              delivery.order.seller.seller_code,
              delivery.order.client.name,
              delivery.delivery_address.address,
              delivery.status_humanize,
              delivery.delivery_type_humanize
            ]
          end
        end
      end
  end

  def status_i18n(status, type)
    case type
    when :delivery
      Delivery.statuses.key(status).humanize # Convierte el valor numérico a string y lo humaniza
    when :order
      Order.statuses.key(status).humanize
    else
      status.to_s.humanize
    end
  end

  private

  def notify_all_confirmed
    return unless confirmed?  # Usa el método que ya tienes

    items = delivery_items
    all_confirmed = items.all? { |di| di.status == "confirmed" }

    if all_confirmed
      users = User.where(role: [ :logistics, :admin ])
      users << delivery_plan.driver if delivery_plan&.driver
      message = "Todos los productos del pedido #{order.number} para la entrega del #{delivery_date.strftime('%d/%m/%Y')} fueron confirmados por el vendedor."
      NotificationService.create_for_users(users.uniq, self, message)
    end
  end

  def self.status_options_for_select
    statuses.keys.map do |s|
      [ Delivery.new(status: s).display_status, s ]
    end
  end
end
