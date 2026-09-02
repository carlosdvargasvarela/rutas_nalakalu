module Api
  module V1
    module Driver
      class AssignmentsController < BaseController
        before_action :set_assignment

        def start
          handle_lock { @assignment.start! }
          render_ok("Entrega iniciada")
        end

        def complete
          handle_lock { @assignment.complete! }
          render_ok("Entrega completada")
        end

        def fail
          reason = params[:reason].presence || "No especificado"
          handle_lock { @assignment.mark_as_failed!(reason: reason, failed_by: current_user) }
          render_ok("Entrega marcada como fallida")
        end

        def add_note
          note = params[:note].presence
          if note.blank?
            render json: {success: false, error: "La nota no puede estar vacía"},
                   status: :unprocessable_entity
            return
          end
          handle_lock { @assignment.add_driver_note!(note) }
          render_ok("Nota agregada")
        end

        private

        def set_assignment
          @assignment = DeliveryPlanAssignment.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: {error: "Parada no encontrada"}, status: :not_found
        end

        def handle_lock
          yield
        rescue ActiveRecord::StaleObjectError
          render json: {success: false, error: "El recurso fue modificado. Recarga la app."},
                 status: :conflict
        rescue ActiveRecord::RecordInvalid => e
          render json: {success: false, error: e.message}, status: :unprocessable_entity
        end

        def render_ok(message)
          render json: {
            success: true,
            message: message,
            assignment: {
              id: @assignment.id,
              status: @assignment.status,
              started_at: @assignment.started_at&.iso8601,
              completed_at: @assignment.completed_at&.iso8601,
              driver_notes: @assignment.driver_notes,
              lock_version: @assignment.lock_version
            }
          }
        end
      end
    end
  end
end
