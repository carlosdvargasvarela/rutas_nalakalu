# app/models/delivery_plan_assignment.rb
# frozen_string_literal: true

class DeliveryPlanAssignment < ApplicationRecord
  include HasDisplayStatus

  DISPLAY_STATUS_LABELS = {
    "pending" => "Pendiente",
    "in_route" => "En ruta",
    "completed" => "Completado",
    "cancelled" => "Cancelado"
  }.freeze

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
  after_update_commit :broadcast_progress_update, if: :saved_change_to_status?

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

  # Otras paradas del mismo plan en el mismo lugar físico: comparten
  # stop_order porque DeliveryPlanStopGrouper ya las agrupó por proximidad
  # GPS al armar la ruta. Es la señal de "mismo lugar" confiable (por ID,
  # no por texto de dirección).
  def same_stop_siblings
    return DeliveryPlanAssignment.none if stop_order.nil?

    delivery_plan.delivery_plan_assignments
      .where(stop_order: stop_order)
      .where.not(id: id)
  end

  # Inicia la parada: marca el assignment y la entrega como "en ruta"
  # IDEMPOTENTE: retorna true si ya está in_route o completed
  def start!
    return true if in_route? || completed?

    transaction do
      update!(status: :in_route, started_at: Time.current)

      if delivery.in_plan? || delivery.ready_to_deliver?
        delivery.update!(status: :in_route)
      end

      # No solo :in_plan -- un item que quedó en :pending/:confirmed (ej. se
      # agregó a la entrega después de crear el assignment, sin pasar por
      # change_deliveries_statuses) hace que update_status_based_on_items
      # regrese la entrega a :in_plan más abajo, aunque el assignment ya
      # esté in_route.
      delivery.delivery_items
        .where(status: DeliveryItem.statuses.values_at("pending", "confirmed", "in_plan"))
        .find_each { |item| item.update!(status: :in_route) }

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

  # Completa la parada: marca todos los items como entregados.
  # Si quedan items en un estado raro (ej. missing) y la entrega no llega a
  # un estado terminal real, el assignment se queda in_route en vez de
  # completed — así no cierra el plan solo con paradas a medias.
  # IDEMPOTENTE: retorna true si ya está completed
  def complete!
    return true if completed?

    success = false

    transaction do
      delivery.mark_as_delivered!
      delivery.reload

      if delivery.terminal?
        update!(status: :completed, completed_at: Time.current)

        DeliveryEvent.record(
          delivery: delivery,
          action: "delivered",
          actor: AuditActor.current,
          payload: {via: "plan_assignment"}
        )

        finish_plan_if_done
        success = true
      end
    end

    success
  end

  # Marca la parada como fallida y ejecuta el servicio de fallo
  # IDEMPOTENTE: retorna true si ya está cancelled o completed
  def mark_as_failed!(reason: nil, failed_by: nil)
    return true if completed? || cancelled?

    transaction do
      # El servicio maneja el cambio de estados de delivery e items
      DeliveryFailureService.new(delivery, reason: reason, failed_by: failed_by).call

      # Marcamos el assignment como cancelado porque la parada fracasó
      update!(status: :cancelled, completed_at: Time.current)

      # Recalcular estado del delivery tras el fallo
      delivery.reload.update_status_based_on_items

      finish_plan_if_done
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


  # ============================================================================
  # MÉTODOS PRIVADOS
  # ============================================================================

  private

  # Al cerrar la última parada el plan se completa solo (apaga el seguimiento GPS)
  def finish_plan_if_done
    delivery_plan.reload.finish! if delivery_plan.status_in_progress?
  end

  # Callback al crear el assignment: cambia los items confirmados a in_plan
  def change_deliveries_statuses
    # Si el plan está en draft y la entrega en scheduled, no cambiar estados aún
    return if delivery_plan.draft? && delivery.scheduled?

    transaction do
      delivery.delivery_items.where(status: DeliveryItem.statuses[:confirmed]).find_each do |item|
        item.update!(status: :in_plan)
      end

      delivery.update!(status: :in_plan)

      delivery.update_status_based_on_items
    end
  end

  # Callback al destruir el assignment: revierte los items de in_plan a confirmed
  def revert_statuses
    transaction do
      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan]).find_each do |item|
        item.update!(status: :confirmed)
      end

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

  def broadcast_progress_update
    delivery_plan.broadcast_replace_to(
      delivery_plan,
      target: "delivery_progress",
      partial: "delivery_plans/show_partials/progress_section",
      locals: {delivery_plan: delivery_plan, assignments: delivery_plan.delivery_plan_assignments.includes(:delivery)}
    )

    # Le permite a la página pública de tracking del cliente (que ya está
    # suscrita a este mismo canal para la posición del camión) reaccionar
    # en vivo cuando SU parada pasa a in_route, sin tener que recargar.
    DeliveryPlanChannel.broadcast_to(delivery_plan, {
      type: "assignment_update",
      delivery_id: delivery_id,
      status: status
    })
  end
end
