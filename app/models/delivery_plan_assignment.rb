# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  after_create :change_deliveries_statuses
  after_destroy :revert_statuses

  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order

  enum status: { pending: 0, en_route: 1, completed: 2, cancelled: 3 }, _default: :pending

  # ============================================================================
  # MÉTODOS PÚBLICOS
  # ============================================================================

  # Inicia la parada: marca el assignment y la entrega como "en ruta"
  def start!
    return if en_route? || completed?

    transaction do
      update!(status: :en_route, started_at: Time.current)

      # Cambiar delivery a in_route si está en plan o listo
      if delivery.in_plan? || delivery.ready_to_deliver?
        delivery.update_column(:status, Delivery.statuses[:in_route])
      end

      # Cambiar items de in_plan a in_route
      delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan])
              .update_all(status: DeliveryItem.statuses[:in_route], updated_at: Time.current)

      # Recalcular estado del delivery explícitamente
      delivery.update_status_based_on_items
    end
  end

  # Completa la parada: marca todos los items como entregados
  def complete!
    return if completed?

    transaction do
      delivery.mark_as_delivered!
      update!(status: :completed, completed_at: Time.current)
    end
  end

  # Agrega una nota del chofer
  def add_driver_note!(note)
    update!(driver_notes: [ driver_notes, note ].compact_blank.join("\n"))
  end

  # Marca la parada como fallida y ejecuta el servicio de fallo
  def mark_as_failed!(reason: nil)
    return if completed?

    transaction do
      # El servicio maneja el cambio de estados de delivery e items
      DeliveryFailureService.new(delivery, reason: reason).call

      # Marcamos el assignment como cancelado porque la parada fracasó
      update!(status: :cancelled, completed_at: Time.current)

      # Recalcular estado del delivery tras el fallo
      delivery.reload.update_status_based_on_items
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
end
