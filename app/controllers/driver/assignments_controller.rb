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

    def mark_failed
      authorize [ :driver, @plan ], :assignment_action?

      reason = params[:reason].presence || "Entrega fracasada reportada por chofer"
      new_delivery = @assignment.mark_as_failed!(reason: reason)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("assignment_#{@assignment.id}",
              partial: "driver/delivery_plans/assignment",
              locals: { assignment: @assignment }),
            turbo_stream.replace("driver_progress_counter") do
              tag.span(class: "small text-muted") do
                render "driver/delivery_plans/progress_counter", plan: @plan
              end
            end,
            turbo_stream.append("flash") do
              tag.div(class: "alert alert-warning alert-dismissible fade show mt-2", role: "alert") do
                concat "Entrega marcada como fracasada. Nueva entrega creada para #{new_delivery.delivery_date.strftime('%d/%m/%Y')}."
                concat tag.button(type: "button", class: "btn-close", data: { bs_dismiss: "alert" })
              end
            end
          ]
        end
        format.html { redirect_to driver_delivery_plan_path(@plan), notice: "Entrega marcada como fracasada. Nueva entrega creada para #{new_delivery.delivery_date.strftime('%d/%m/%Y')}." }
      end
    end

    private

    def set_resources
      @plan = DeliveryPlan.find(params[:delivery_plan_id])
      @assignment = @plan.delivery_plan_assignments.find(params[:id])
    end
  end
end
