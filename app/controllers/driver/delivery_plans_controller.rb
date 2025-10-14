module Driver
  class DeliveryPlansController < ApplicationController
    layout "driver"
    before_action :authenticate_user!
    before_action :set_plan
    after_action :verify_authorized

    def show
      authorize [ :driver, @plan ]
      @assignments = @plan.delivery_plan_assignments
                          .includes(delivery: [ :delivery_items, { order: [ :client, :seller ] }, { delivery_address: :client } ])
                          .order(:stop_order)
      @completed_count = @assignments.completed.count
    end

    def start_route
      authorize [ :driver, @plan ], :start_route?
      first_pending = @plan.delivery_plan_assignments.order(:stop_order).pending.first
      if first_pending
        first_pending.start!
        redirect_to driver_delivery_plan_path(@plan), notice: "Ruta iniciada. Primera parada en estado En ruta."
      else
        redirect_to driver_delivery_plan_path(@plan), alert: "No hay paradas pendientes."
      end
    end

    private

    def set_plan
      @plan = DeliveryPlan.find(params[:id])
    end
  end
end
