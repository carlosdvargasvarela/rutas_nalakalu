# frozen_string_literal: true

# app/controllers/driver/assignments_controller.rb

module Driver
  class AssignmentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_assignment
    after_action :verify_authorized

    # PATCH /driver/assignments/:id/complete
    def complete
      authorize [:driver, @assignment]

      handle_optimistic_lock do
        @assignment.complete!
        render_success("Entrega completada")
      end
    end

    # PATCH /driver/assignments/:id/fail
    def fail
      authorize [:driver, @assignment]

      reason = params[:reason].presence || "No especificado"

      handle_optimistic_lock do
        @assignment.mark_as_failed!(reason: reason, failed_by: current_user)
        render_success("Entrega marcada como fallida")
      end
    end

    # PATCH /driver/assignments/:id/add_note
    def add_note
      authorize [:driver, @assignment]

      note_text = params[:note].presence

      if note_text.blank?
        render json: {
          success: false,
          error: "La nota no puede estar vacía"
        }, status: :unprocessable_entity
        return
      end

      handle_optimistic_lock do
        @assignment.add_driver_note!(note_text)
        render_success("Nota agregada correctamente")
      end
    end

    private

    def set_assignment
      @assignment = DeliveryPlanAssignment.find(params[:id])
    end

    def handle_optimistic_lock
      yield
    rescue Pundit::NotAuthorizedError
      render json: {
        success: false,
        error: "No autorizado"
      }, status: :forbidden
    rescue ActiveRecord::StaleObjectError
      render json: {
        success: false,
        error: "El recurso fue modificado por otro proceso. Recarga la página.",
        assignment: assignment_json(@assignment.reload)
      }, status: :conflict
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        success: false,
        error: e.message
      }, status: :unprocessable_entity
    rescue => e
      render json: {
        success: false,
        error: e.message
      }, status: :unprocessable_entity
    end

    def render_success(message)
      render json: {
        success: true,
        message: message,
        assignment: assignment_json(@assignment),
        progress: progress_json
      }, status: :ok
    end

    def assignment_json(assignment)
      delivery = assignment.delivery
      addr = delivery.delivery_address

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
          address: addr ? {
            text: addr.address,
            description: addr.description,
            lat: addr.latitude,
            lng: addr.longitude,
            plus_code: addr.plus_code
          } : nil
        }
      }
    end

    def progress_json
      delivery_plan = @assignment.delivery_plan
      assignments = delivery_plan.delivery_plan_assignments

      {
        completed: assignments.count(&:completed?),
        in_route: assignments.count(&:in_route?),
        pending: assignments.count(&:pending?),
        failed: assignments.count(&:cancelled?),
        total: assignments.count
      }
    end
  end
end
