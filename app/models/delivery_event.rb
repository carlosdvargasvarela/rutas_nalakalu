# app/models/delivery_event.rb
class DeliveryEvent < ApplicationRecord
  self.table_name = "delivery_events"

  # =========================================================================
  # Asociaciones
  # =========================================================================
  belongs_to :delivery
  belongs_to :actor, class_name: "User", optional: true

  # =========================================================================
  # Validaciones
  # =========================================================================
  validates :action, presence: true
  validates :delivery_id, presence: true

  # =========================================================================
  # Constantes de acciones
  # =========================================================================
  ACTIONS = %w[
    rescheduled
    item_rescheduled
    sala_pickup_created
    service_case_created
    approved
    delivered
    warehousing_started
    warehousing_ended
    seller_reassigned
    created
    updated
    cancelled
    archived
  ].freeze

  # =========================================================================
  # Scopes
  # =========================================================================
  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }
  scope :by_actor, ->(user_id) { where(actor_id: user_id) }

  # =========================================================================
  # Payload helpers
  # =========================================================================

  # Deserializa el payload JSON de forma segura
  def payload_data
    return {} if payload.blank?
    JSON.parse(payload)
  rescue JSON::ParserError => e
    Rails.logger.error("DeliveryEvent#payload_data error: #{e.message}")
    {}
  end

  # =========================================================================
  # Factory method — punto único de creación
  # =========================================================================

  # Uso:
  #   DeliveryEvent.record(
  #     delivery: delivery,
  #     action: "rescheduled",
  #     actor: current_user,
  #     payload: { reason: "...", new_date: "..." }
  #   )
  def self.record(delivery:, action:, actor: nil, payload: {})
    create!(
      delivery: delivery,
      action: action,
      actor: actor,
      payload: payload.to_json,
      created_at: Time.current
    )
  rescue => e
    Rails.logger.error("❌ DeliveryEvent.record falló [#{action}] delivery=#{delivery&.id}: #{e.message}")
    nil
  end

  # =========================================================================
  # Presentación
  # =========================================================================

  ACTION_LABELS = {
    "rescheduled" => "Reagendada",
    "item_rescheduled" => "Ítem reagendado",
    "sala_pickup_created" => "Recogida en Sala creada",
    "service_case_created" => "Caso de servicio creado",
    "approved" => "Aprobada",
    "delivered" => "Marcada como entregada",
    "warehousing_started" => "Bodegaje iniciado",
    "warehousing_ended" => "Bodegaje finalizado",
    "seller_reassigned" => "Vendedor reasignado",
    "created" => "Creada",
    "updated" => "Actualizada",
    "cancelled" => "Cancelada",
    "archived" => "Archivada"
  }.freeze

  ACTION_COLORS = {
    "rescheduled" => "warning",
    "item_rescheduled" => "warning",
    "sala_pickup_created" => "info",
    "service_case_created" => "info",
    "approved" => "success",
    "delivered" => "success",
    "warehousing_started" => "secondary",
    "warehousing_ended" => "secondary",
    "seller_reassigned" => "primary",
    "created" => "success",
    "updated" => "primary",
    "cancelled" => "danger",
    "archived" => "dark"
  }.freeze

  ACTION_ICONS = {
    "rescheduled" => "bi-calendar-x",
    "item_rescheduled" => "bi-box-arrow-right",
    "sala_pickup_created" => "bi-shop",
    "service_case_created" => "bi-tools",
    "approved" => "bi-check-circle",
    "delivered" => "bi-truck",
    "warehousing_started" => "bi-box-seam",
    "warehousing_ended" => "bi-box-arrow-up",
    "seller_reassigned" => "bi-person-badge",
    "created" => "bi-plus-circle",
    "updated" => "bi-pencil",
    "cancelled" => "bi-x-circle",
    "archived" => "bi-archive"
  }.freeze

  def label
    ACTION_LABELS[action] || action.humanize
  end

  def color
    ACTION_COLORS[action] || "secondary"
  end

  def icon
    ACTION_ICONS[action] || "bi-circle"
  end

  def actor_name
    actor&.name || "Sistema"
  end
end
