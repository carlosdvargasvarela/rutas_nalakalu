module Api
  module V1
    module Driver
      class DeliveryPlansController < BaseController
        before_action :set_plan, only: [:show, :start, :finish, :abort, :update_position_batch]

        def index
          delivered_status = Delivery.statuses[:delivered]
          plans = DeliveryPlan
            .for_driver(current_user.id)
            .left_joins(:deliveries)
            .select(<<~SQL)
              delivery_plans.*,
              COUNT(deliveries.id) AS deliveries_count,
              COUNT(CASE WHEN deliveries.status = #{delivered_status} THEN 1 END) AS delivered_count,
              MIN(deliveries.delivery_date) AS first_delivery_date_val
            SQL
            .group("delivery_plans.id")
            .order(Arel.sql("MAX(deliveries.delivery_date) DESC NULLS LAST, delivery_plans.created_at DESC"))

          render json: plans.map { |p| serialize_summary(p) }
        end

        def show
          assignments = @plan.delivery_plan_assignments
            .includes(delivery: [:delivery_address, {order: [:client]}])
            .order(:stop_order)

          render json: serialize_detail(@plan, assignments)
        end

        def start
          if @plan.start!
            render json: {ok: true, status: @plan.status}
          else
            render json: {ok: false, error: "No se pudo iniciar el plan"}, status: :unprocessable_entity
          end
        rescue ActiveRecord::StaleObjectError
          render json: {ok: false, error: "El plan fue modificado, recarga"}, status: :conflict
        end

        def finish
          if @plan.finish!
            render json: {ok: true, status: @plan.status}
          else
            render json: {ok: false, error: "No se pudo completar el plan"}, status: :unprocessable_entity
          end
        rescue ActiveRecord::StaleObjectError
          render json: {ok: false, error: "El plan fue modificado, recarga"}, status: :conflict
        end

        def abort
          if @plan.abort!
            render json: {ok: true, status: @plan.status}
          else
            render json: {ok: false, error: "No se pudo abortar el plan"}, status: :unprocessable_entity
          end
        rescue ActiveRecord::StaleObjectError
          render json: {ok: false, error: "El plan fue modificado, recarga"}, status: :conflict
        end

        def update_position_batch
          positions = params[:positions] || []
          saved_count = 0

          positions.each do |pos|
            loc = @plan.delivery_plan_locations.create(
              latitude:    pos[:latitude],
              longitude:   pos[:longitude],
              accuracy:    pos[:accuracy],
              speed:       pos[:speed],
              heading:     pos[:heading],
              captured_at: pos[:timestamp] || Time.current,
              source:      "batch"
            )
            saved_count += 1 if loc.persisted?
          end

          if positions.any?
            last = positions.last
            @plan.update_columns(
              current_lat: last[:latitude]&.to_f,
              current_lng: last[:longitude]&.to_f,
              last_seen_at: Time.current
            )
            DeliveryPlanChannel.broadcast_to(@plan, {
              type: "position_update",
              current_lat: @plan.current_lat,
              current_lng: @plan.current_lng,
              last_seen_at: @plan.last_seen_at
            })
          end

          render json: {success: true, saved: saved_count, total: positions.size}
        end

        private

        def set_plan
          @plan = DeliveryPlan.for_driver(current_user.id).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: {error: "Plan no encontrado"}, status: :not_found
        end

        def serialize_summary(plan)
          {
            id: plan.id,
            status: plan.status,
            status_label: plan.display_status,
            truck: plan.truck_label,
            week: plan.week,
            year: plan.year,
            deliveries_count: plan.deliveries_count.to_i,
            delivered_count: plan.delivered_count.to_i,
            first_delivery_date: plan.attributes["first_delivery_date_val"]&.to_s,
            updated_at: plan.updated_at.iso8601
          }
        end

        def serialize_detail(plan, assignments)
          {
            id: plan.id,
            status: plan.status,
            status_label: plan.display_status,
            truck: plan.truck_label,
            week: plan.week,
            year: plan.year,
            current_lat: plan.current_lat,
            current_lng: plan.current_lng,
            last_seen_at: plan.last_seen_at&.iso8601,
            progress: plan.progress,
            assignments: assignments.map { |a| serialize_assignment(a) }
          }
        end

        def serialize_assignment(a)
          d = a.delivery
          addr = d.delivery_address
          {
            id: a.id,
            stop_order: a.stop_order,
            status: a.status,
            status_label: a.display_status,
            started_at: a.started_at&.iso8601,
            completed_at: a.completed_at&.iso8601,
            driver_notes: a.driver_notes,
            lock_version: a.lock_version,
            delivery: {
              id: d.id,
              order_number: d.order&.number,
              client_name: d.order&.client&.name,
              contact_name: d.contact_name,
              contact_phone: d.contact_phone,
              delivery_notes: d.delivery_notes,
              delivery_date: d.delivery_date&.iso8601,
              delivery_time_preference: d.delivery_time_preference,
              address: addr ? {
                text: addr.address,
                description: addr.description,
                lat: addr.latitude&.to_f,
                lng: addr.longitude&.to_f,
                plus_code: addr.plus_code
              } : nil
            }
          }
        end
      end
    end
  end
end
