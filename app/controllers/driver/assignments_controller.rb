# frozen_string_literal: true

module Driver
  class AssignmentsController < ApplicationController
    layout false
    before_action :authenticate_user!
    before_action :set_delivery_plan
    before_action :set_assignment
    after_action :verify_authorized

    def start
      authorize [ :driver, @assignment ]

      handle_optimistic_lock do
        @assignment.start!
        render_success("Entrega iniciada")
      end
    end

    def complete
      authorize [ :driver, @assignment ]

      handle_optimistic_lock do
        @assignment.complete!
        render_success("Entrega completada")
      end
    end

    def mark_failed
      authorize [ :driver, @assignment ]

      handle_optimistic_lock do
        @assignment.mark_as_failed!(reason: params[:reason])
        render_success("Entrega marcada como fallida")
      end
    end

    def note
      authorize [ :driver, @assignment ]

      note_text = params.dig(:note, :text)
      if note_text.blank?
        render json: { ok: false, error: "La nota no puede estar vacía" }, status: :unprocessable_entity
        return
      end

      handle_optimistic_lock do
        @assignment.add_driver_note!(note_text)
        render_success("Nota agregada")
      end
    end

    private

    def set_delivery_plan
      # FIX: usar :delivery_plan_id (venía como :plan_id)
      @delivery_plan = DeliveryPlan.find(params[:delivery_plan_id])
    end

    def set_assignment
      @assignment = @delivery_plan.delivery_plan_assignments.find(params[:id])
    end

    def handle_optimistic_lock
      yield
    rescue ActiveRecord::StaleObjectError
      render json: {
        ok: false,
        error: "El recurso fue modificado por otro usuario. Recargando datos...",
        assignment: assignment_json(@assignment.reload)
      }, status: :conflict
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def render_success(message)
      render json: {
        ok: true,
        message: message,
        assignment: assignment_json(@assignment),
        progress: progress_json
      }, status: :ok
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
        lock_version: assignment.lock_version,
        delivery: {
          id: delivery.id,
          status: delivery.status,
          delivery_date: delivery.delivery_date&.iso8601,
          contact_name: delivery.contact_name,
          contact_phone: delivery.contact_phone,
          delivery_notes: delivery.delivery_notes,
          delivery_time_preference: delivery.delivery_time_preference,
          order_number: delivery.order&.number,
          client_name: delivery.order&.client&.name,
          address: address ? {
            text: address.address,
            description: address.description,
            lat: address.latitude,
            lng: address.longitude,
            plus_code: address.plus_code
          } : nil
        }
      }
    end

    def progress_json
      assignments = @delivery_plan.delivery_plan_assignments
      {
        completed: assignments.count(&:completed?),
        en_route: assignments.count(&:en_route?),
        pending: assignments.count(&:pending?),
        total: assignments.count
      }
    end
  end

end
