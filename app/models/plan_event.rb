class PlanEvent < ApplicationRecord
  include EventLog

  belongs_to :delivery_plan
  belongs_to :actor, class_name: "User", optional: true

  validates :delivery_plan_id, presence: true

  ACTIONS = %w[
    created
    sent_to_logistics
    routes_created
    started
    finished
    aborted
    stop_added
    stop_removed
  ].freeze

  ACTION_LABELS = {
    "created" => "Plan creado",
    "sent_to_logistics" => "Enviado a logística",
    "routes_created" => "Ruta creada",
    "started" => "Iniciado",
    "finished" => "Finalizado",
    "aborted" => "Abortado",
    "stop_added" => "Parada agregada",
    "stop_removed" => "Parada quitada"
  }.freeze

  ACTION_COLORS = {
    "created" => "success",
    "sent_to_logistics" => "primary",
    "routes_created" => "primary",
    "started" => "info",
    "finished" => "success",
    "aborted" => "danger",
    "stop_added" => "secondary",
    "stop_removed" => "warning"
  }.freeze

  ACTION_ICONS = {
    "created" => "bi-plus-circle",
    "sent_to_logistics" => "bi-send",
    "routes_created" => "bi-signpost-2",
    "started" => "bi-play-circle",
    "finished" => "bi-check-circle",
    "aborted" => "bi-x-circle",
    "stop_added" => "bi-pin-map",
    "stop_removed" => "bi-pin-map-fill"
  }.freeze

  def self.record(delivery_plan:, action:, actor: nil, payload: {})
    record_event(
      delivery_plan: delivery_plan,
      action: action,
      actor: actor,
      payload: payload.to_json
    )
  end
end
