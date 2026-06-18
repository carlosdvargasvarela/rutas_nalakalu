class DeliveryEvent < ApplicationRecord
  include EventLog

  self.table_name = "delivery_events"

  # =========================================================================
  # Asociaciones
  # =========================================================================
  belongs_to :delivery
  belongs_to :actor, class_name: "User", optional: true

  # =========================================================================
  # Validaciones
  # =========================================================================
  validates :delivery_id, presence: true

  # =========================================================================
  # Constantes de acciones
  # =========================================================================
  ACTIONS = %w[
    rescheduled
    item_rescheduled
    items_bulk_confirmed
    sala_pickup_created
    service_case_created
    approved
    delivered
    warehousing_started
    warehousing_ended
    seller_reassigned
    route_started
    failed
    created
    updated
    cancelled
    archived
    reopened
  ].freeze

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
    record_event(
      delivery: delivery,
      action: action,
      actor: actor,
      payload: payload.to_json
    )
  end

  # =========================================================================
  # Presentación
  # =========================================================================

  ACTION_LABELS = {
    "rescheduled" => "Reagendada",
    "item_rescheduled" => "Ítem reagendado",
    "items_bulk_confirmed" => "Ítems confirmados",
    "sala_pickup_created" => "Retiro en Sala programado",
    "service_case_created" => "Caso de servicio creado",
    "approved" => "Aprobada",
    "delivered" => "Marcada como entregada",
    "warehousing_started" => "Bodegaje iniciado",
    "warehousing_ended" => "Bodegaje finalizado",
    "seller_reassigned" => "Vendedor reasignado",
    "route_started" => "En ruta (parada de plan iniciada)",
    "failed" => "Entrega fracasada",
    "created" => "Creada",
    "updated" => "Actualizada",
    "cancelled" => "Cancelada",
    "archived" => "Archivada",
    "reopened" => "Reabierta"
  }.freeze

  ACTION_COLORS = {
    "rescheduled" => "warning",
    "item_rescheduled" => "warning",
    "items_bulk_confirmed" => "success",
    "sala_pickup_created" => "info",
    "service_case_created" => "info",
    "approved" => "success",
    "delivered" => "success",
    "warehousing_started" => "secondary",
    "warehousing_ended" => "secondary",
    "seller_reassigned" => "primary",
    "route_started" => "info",
    "failed" => "danger",
    "created" => "success",
    "updated" => "primary",
    "cancelled" => "danger",
    "archived" => "dark",
    "reopened" => "warning"
  }.freeze

  ACTION_ICONS = {
    "rescheduled" => "bi-calendar-x",
    "item_rescheduled" => "bi-box-arrow-right",
    "items_bulk_confirmed" => "bi-check2-all",
    "sala_pickup_created" => "bi-shop",
    "service_case_created" => "bi-tools",
    "approved" => "bi-check-circle",
    "delivered" => "bi-truck",
    "warehousing_started" => "bi-box-seam",
    "warehousing_ended" => "bi-box-arrow-up",
    "seller_reassigned" => "bi-person-badge",
    "route_started" => "bi-truck",
    "failed" => "bi-exclamation-triangle",
    "created" => "bi-plus-circle",
    "updated" => "bi-pencil",
    "cancelled" => "bi-x-circle",
    "archived" => "bi-archive",
    "reopened" => "bi-arrow-counterclockwise"
  }.freeze
end
