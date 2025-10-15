# frozen_string_literal: true

module Driver
  class AssignmentsController < ApplicationController
    layout "driver"
    before_action :authenticate_user!
    before_action :set_delivery_plan
    before_action :set_assignment
    after_action :verify_authorized

    def start
      authorize @assignment, policy_class: Driver::AssignmentPolicy

      request_id = request.headers["X-Request-Id"]
      if request_id && duplicate_request?(request_id)
        return render_success_response("start")
      end

      @assignment.start!
      log_request(request_id) if request_id

      render_success_response("start")
    rescue StateMachines::InvalidTransition => e
      render_error_response(e.message, :unprocessable_entity)
    end

    def complete
      authorize @assignment, policy_class: Driver::AssignmentPolicy

      request_id = request.headers["X-Request-Id"]
      if request_id && duplicate_request?(request_id)
        return render_success_response("complete")
      end

      @assignment.complete!
      log_request(request_id) if request_id

      render_success_response("complete")
    rescue StateMachines::InvalidTransition => e
      render_error_response(e.message, :unprocessable_entity)
    end

    def mark_failed
      authorize @assignment, policy_class: Driver::AssignmentPolicy

      request_id = request.headers["X-Request-Id"]
      if request_id && duplicate_request?(request_id)
        return render_success_response("mark_failed")
      end

      @assignment.mark_as_failed!
      log_request(request_id) if request_id

      render_success_response("mark_failed")
    rescue StateMachines::InvalidTransition => e
      render_error_response(e.message, :unprocessable_entity)
    end

    def note
      authorize @assignment, policy_class: Driver::AssignmentPolicy

      request_id = request.headers["X-Request-Id"]
      if request_id && duplicate_request?(request_id)
        return render_success_response("note")
      end

      note_text = params.require(:note).permit(:text)[:text]
      @assignment.add_driver_note!(note_text)
      log_request(request_id) if request_id

      render_success_response("note")
    rescue ActiveRecord::RecordInvalid => e
      render_error_response(e.message, :unprocessable_entity)
    end

    private

    def set_delivery_plan
      @delivery_plan = DeliveryPlan.find(params[:delivery_plan_id])
    end

    def set_assignment
      @assignment = @delivery_plan.delivery_plan_assignments.find(params[:id])
    end

    def duplicate_request?(request_id)
      Rails.cache.exist?(cache_key_for_request(request_id))
    end

    def log_request(request_id)
      # Guardar en cache por 48 horas
      Rails.cache.write(
        cache_key_for_request(request_id),
        { user_id: current_user.id, timestamp: Time.current.to_i },
        expires_in: 48.hours
      )
    end

    def cache_key_for_request(request_id)
      "request_log:#{current_user.id}:#{request.path}:#{request.method}:#{request_id}"
    end

    def render_success_response(action)
      @assignments = @delivery_plan.delivery_plan_assignments
                                   .includes(delivery: [ :delivery_address, :delivery_items ])
                                   .order(:stop_order)

      respond_to do |format|
        format.html do
          render turbo_stream: [
            turbo_stream.replace(
              "assignment_#{@assignment.id}",
              partial: "driver/delivery_plans/assignment_card",
              locals: { assignment: @assignment, delivery_plan: @delivery_plan }
            ),
            turbo_stream.replace(
              "plan_progress",
              partial: "driver/delivery_plans/progress",
              locals: { delivery_plan: @delivery_plan, assignments: @assignments }
            )
          ]
        end

        format.json do
          render json: {
            ok: true,
            action: action,
            assignment: assignment_json(@assignment),
            progress: {
              completed: @assignments.count(&:completed?),
              total: @assignments.count
            }
          }
        end
      end
    end

    def render_error_response(message, status)
      respond_to do |format|
        format.html do
          render turbo_stream: turbo_stream.replace(
            "flash",
            partial: "shared/flash",
            locals: { flash: { alert: message } }
          ), status: status
        end

        format.json do
          render json: { ok: false, error: message }, status: status
        end
      end
    end

    def assignment_json(assignment)
      delivery = assignment.delivery
      address = delivery.delivery_address

      {
        id: assignment.id,
        delivery_id: delivery.id,
        stop_order: assignment.stop_order,
        status: assignment.status,
        started_at: assignment.started_at&.iso8601,
        completed_at: assignment.completed_at&.iso8601,
        driver_notes: assignment.driver_notes,
        delivery: {
          id: delivery.id,
          status: delivery.status,
          delivery_date: delivery.delivery_date&.iso8601,
          contact_name: delivery.contact_name,
          contact_phone: delivery.contact_phone,
          delivery_notes: delivery.delivery_notes,
          delivery_time_preference: delivery.delivery_time_preference,
          address: address ? {
            text: address.address_text,
            lat: address.latitude,
            lng: address.longitude,
            plus_code: address.plus_code
          } : nil,
          items: delivery.delivery_items.map { |item|
            {
              id: item.id,
              product: item.product,
              quantity: item.quantity,
              service_case: item.service_case,
              notes: item.notes
            }
          }
        }
      }
    end
  end
end
