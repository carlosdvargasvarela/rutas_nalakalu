# app/models/delivery_plan_assignment.rb
# frozen_string_literal: true

class DeliveryPlanAssignment < ApplicationRecord
  # Versionado y auditoría
  has_paper_trail

  # Asociaciones
  belongs_to :delivery_plan
  belongs_to :delivery

  # Callbacks
  after_create :change_deliveries_statuses
  after_create :record_stop_added
  after_destroy :revert_statuses
  after_destroy :record_stop_removed

  # Validaciones
  validates :stop_order, numericality: {only_integer: true, allow_nil: true}

  # Ordenamiento
  acts_as_list scope: :delivery_plan, column: :stop_order

  enum status: {
    pending: 0,
    in_route: 1,
    completed: 2,
    cancelled: 3
  }, _default: :pending

  # Scopes
  scope :ordered, -> { order(:stop_order) }

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  # Inicia la parada: marca el assignment y la entrega como "en ruta"
  # IDEMPOTENTE: retorna true si ya está in_route o completed
  def start!
    return true if in_route? || completed?

    transaction do
      update!(status: :in_route, started_at: Time.current)

      if delivery.in_plan? || delivery.ready_to_deliver?
        delivery.update!(status: :in_route)
      end

      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan]).find_each do |item|
        item.update!(status: :in_route)
      end

      delivery.update_status_based_on_items

      DeliveryEvent.record(
        delivery: delivery,
        action: "route_started",
        actor: AuditActor.current,
        payload: {delivery_plan_id: delivery_plan_id, stop_order: stop_order}
      )
    end

    true
  end

  # Completa la parada: marca todos los items como entregados
  # IDEMPOTENTE: retorna true si ya está completed
  def complete!
    return true if completed?

    transaction do
      delivery.mark_as_delivered!
      update!(status: :completed, completed_at: Time.current)
    end

    true
  end

  # Marca la parada como fallida y ejecuta el servicio de fallo
  # IDEMPOTENTE: retorna true si ya está cancelled o completed
  def mark_as_failed!(reason: nil, failed_by: nil)
    return true if completed? || cancelled?

    transaction do
      # El servicio maneja el cambio de estados de delivery e items
      DeliveryFailureService.new(delivery, reason: reason).call

      # Marcamos el assignment como cancelado porque la parada fracasó
      update!(status: :cancelled, completed_at: Time.current)

      # Recalcular estado del delivery tras el fallo
      delivery.reload.update_status_based_on_items
    end

    true
  end

  # Agrega una nota del chofer con timestamp
  def add_driver_note!(note)
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
    new_note = "[#{timestamp}] #{note}"

    current = driver_notes.to_s.strip
    updated =
      if current.blank?
        new_note
      else
        "#{current}\n#{new_note}"
      end

    update!(driver_notes: updated)
  end

  # Etiqueta legible del estado
  def display_status
    case status
    when "pending" then "Pendiente"
    when "in_route" then "En ruta"
    when "completed" then "Completado"
    when "cancelled" then "Cancelado"
    else status.to_s.humanize
    end
  end

  # ============================================================================
  # MÉTODOS PRIVADOS
  # ============================================================================

  private

  # Callback al crear el assignment: cambia los items confirmados a in_plan
  def change_deliveries_statuses
    # Si el plan está en draft y la entrega en scheduled, no cambiar estados aún
    return if delivery_plan.draft? && delivery.scheduled?

    transaction do
      # Cambiar items confirmados a in_plan
      delivery.delivery_items.where(status: DeliveryItem.statuses[:confirmed])
        .update_all(status: DeliveryItem.statuses[:in_plan], updated_at: Time.current)

      # Cambiar delivery a in_plan
      delivery.update_column(:status, Delivery.statuses[:in_plan])

      # Recalcular estado del delivery explícitamente
      delivery.update_status_based_on_items
    end
  end

  # Callback al destruir el assignment: revierte los items de in_plan a confirmed
  def revert_statuses
    transaction do
      # Revertir items de in_plan a confirmed
      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan])
        .update_all(status: DeliveryItem.statuses[:confirmed], updated_at: Time.current)

      # Recalcular estado del delivery explícitamente
      delivery.update_status_based_on_items
    end
  end

  def record_stop_added
    PlanEvent.record(
      delivery_plan: delivery_plan,
      action: "stop_added",
      actor: AuditActor.current,
      payload: {delivery_id: delivery_id, delivery_label: delivery_label_for_event}
    )
  end

  def record_stop_removed
    PlanEvent.record(
      delivery_plan: delivery_plan,
      action: "stop_removed",
      actor: AuditActor.current,
      payload: {delivery_id: delivery_id, delivery_label: delivery_label_for_event}
    )
  end

  def delivery_label_for_event
    "Pedido #{delivery.order_number} — #{delivery.delivery_address&.address}"
  rescue StandardError
    "Entrega ##{delivery_id}"
  end
end
