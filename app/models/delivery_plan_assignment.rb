class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  after_create :change_deliveries_statuses
  after_destroy :revert_statuses

  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order

  enum status: { pending: 0, en_route: 1, completed: 2, cancelled: 3 }, _default: :pending

  def start!
    return if en_route? || completed?
    transaction do
      update!(status: :en_route, started_at: Time.current)
      delivery.update!(status: :in_route) if delivery.in_plan? || delivery.ready_to_deliver?
      delivery.delivery_items.where(status: :in_plan).update_all(status: DeliveryItem.statuses[:in_route], updated_at: Time.current)
    end
  end

  def complete!
    return if completed?
    transaction do
      delivery.mark_as_delivered!
      update!(status: :completed, completed_at: Time.current)
    end
  end

  def add_driver_note!(note)
    update!(driver_notes: [ driver_notes, note ].compact_blank.join("\n"))
  end

  def mark_as_failed!(reason: nil)
    return if completed?

    DeliveryFailureService.new(delivery, reason: reason).call.tap do
      # El assignment actual no se completa; lo marcamos como cancelled porque la parada fracasó
      update!(status: :cancelled, completed_at: Time.current)
    end
  end

  private

  def change_deliveries_statuses
    unless delivery_plan.draft? && delivery.scheduled?
      raise ActiveRecord::RecordInvalid, "Entrega no aprobada" unless delivery.approved?

      delivery.delivery_items.where(status: DeliveryItem.statuses[:confirmed])
             .update_all(status: DeliveryItem.statuses[:in_plan], updated_at: Time.current)

      delivery.update_columns(status: Delivery.statuses[:in_plan], updated_at: Time.current)
    end
  end

  def revert_statuses
    delivery.delivery_items.where(status: DeliveryItem.statuses[:in_plan])
           .update_all(status: DeliveryItem.statuses[:confirmed], updated_at: Time.current)
    delivery.update_status_based_on_items
  end
end
