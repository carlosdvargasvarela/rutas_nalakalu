# app/models/delivery_plan_assignment.rb
class DeliveryPlanAssignment < ApplicationRecord
  has_paper_trail
  belongs_to :delivery_plan
  belongs_to :delivery

  after_create :change_deliveries_statuses
  before_destroy :revert_statuses

  validates :stop_order, numericality: { only_integer: true, allow_nil: true }

  acts_as_list scope: :delivery_plan, column: :stop_order

  private

  def change_deliveries_statuses
    unless delivery_plan.draft? && delivery.scheduled?
      # ✅ Solo actualizar los items confirmados a in_plan
      delivery.delivery_items
              .where(status: DeliveryItem.statuses[:confirmed])
              .update_all(status: DeliveryItem.statuses[:in_plan])

      delivery.update_columns(status: Delivery.statuses[:in_plan])
    end
  end

  def revert_statuses
    # ✅ Solo revertir los items que están en plan
    delivery.delivery_items
            .where(status: DeliveryItem.statuses[:in_plan])
            .update_all(status: DeliveryItem.statuses[:confirmed])

    # Actualizar el estado del delivery basado en sus items actuales
    delivery.update_status_based_on_items
  end
end
