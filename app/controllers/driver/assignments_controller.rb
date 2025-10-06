module Driver
  class AssignmentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_resources
    after_action :verify_authorized

    def start
      authorize [ :driver, @plan ], :assignment_action?
      @assignment.start!
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Parada ##{@assignment.stop_order} en ruta." }
      end
    end

    def complete
      authorize [ :driver, @plan ], :assignment_action?
      @assignment.complete!
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Parada ##{@assignment.stop_order} completada." }
      end
    end

    def note
      authorize [ :driver, @plan ], :assignment_action?
      @assignment.add_driver_note!(params.require(:note))
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Nota guardada." }
      end
    end

    def reschedule
      authorize [ :driver, @plan ], :assignment_action?
      date = params.require(:delivery).permit(:delivery_date)[:delivery_date]
      reason = params[:reason].presence || "Reprogramado por chofer"
      @assignment.delivery.delivery_items.where.not(status: [ :delivered, :cancelled ]).find_each do |di|
        di.reschedule!(new_date: Date.parse(date))
      end
      @assignment.update!(status: :cancelled)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Parada reagendada." }
      end
    end

    def cancel
      authorize [ :driver, @plan ], :assignment_action?
      @assignment.update!(status: :cancelled)
      @assignment.delivery.update!(status: :cancelled)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Parada cancelada." }
      end
    end

    private

    def set_resources
      @plan = DeliveryPlan.find(params[:delivery_plan_id])
      @assignment = @plan.delivery_plan_assignments.find(params[:id])
    end
  end
end
