module Api
  module V1
    module Driver
      class DeliveryPlansController < BaseController
        ACTIVE_TRACKER_WINDOW = 5.minutes

        before_action :set_plan, only: [:show, :start, :finish, :abort, :update_position_batch, :claim_tracking]

        def index
          delivered_status = Delivery.statuses[:delivered]
          plans = DeliveryPlan
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
            .includes(delivery: [
              :delivery_address,
              {order: [:client, :seller, :order_contacts]},
              {delivery_items: :order_item}
            ])
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

        def claim_tracking
          @plan.update!(last_recorded_by_id: current_user.id)
          render json: {ok: true, active_tracker: nil}
        rescue ActiveRecord::StaleObjectError
          render json: {ok: false, error: "El plan fue modificado, recarga"}, status: :conflict
        end

        def update_position_batch
          if active_tracker_blocking?
            return render json: {
              error: "otro_conductor_activo",
              active_driver_name: @plan.last_recorded_by.name
            }, status: :conflict
          end

          positions = params[:positions] || []
          saved_count = 0

          positions.each do |pos|
            loc = @plan.delivery_plan_locations.create(
              latitude:       pos[:latitude],
              longitude:      pos[:longitude],
              accuracy:       pos[:accuracy],
              speed:          pos[:speed],
              heading:        pos[:heading],
              captured_at:    pos[:timestamp] || Time.current,
              source:         "batch",
              recorded_by_id: current_user.id
            )
            saved_count += 1 if loc.persisted?
          end

          if positions.any?
            last = positions.last
            @plan.update_columns(
              current_lat:         last[:latitude]&.to_f,
              current_lng:         last[:longitude]&.to_f,
              last_seen_at:        Time.current,
              last_recorded_by_id: current_user.id
            )
            DeliveryPlanChannel.broadcast_to(@plan, {
              type: "position_update",
              current_lat: @plan.current_lat,
              current_lng: @plan.current_lng,
              last_seen_at: @plan.last_seen_at,
              recorded_by_name: current_user.name
            })
          end

          render json: {success: true, saved: saved_count, total: positions.size}
        end

        private

        def set_plan
          @plan = DeliveryPlan.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: {error: "Plan no encontrado"}, status: :not_found
        end

        def active_tracker_blocking?
          return false if @plan.last_recorded_by_id.blank?
          return false if @plan.last_recorded_by_id == current_user.id
          return false if @plan.last_seen_at.blank?

          @plan.last_seen_at > ACTIVE_TRACKER_WINDOW.ago
        end

        def active_tracker_for(plan)
          return nil if plan.last_recorded_by_id.blank?
          return nil if plan.last_recorded_by_id == current_user.id
          return nil if plan.last_seen_at.blank?
          return nil unless plan.last_seen_at > ACTIVE_TRACKER_WINDOW.ago

          {name: plan.last_recorded_by.name}
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
            updated_at: plan.updated_at.iso8601,
            active_tracker: active_tracker_for(plan)
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
            active_tracker: active_tracker_for(plan),
            crew: plan.driver&.crew_members.to_a.map { |cm| {name: cm.name, id_number: cm.id_number} } || [],
            assignments: assignments.map { |a| serialize_assignment(a) }
          }
        end

        def serialize_assignment(a)
          d = a.delivery
          addr = d.delivery_address
          order = d.order
          contacts = order&.order_contacts.to_a.sort_by { |c| c.is_primary? ? 0 : 1 }
          contacts_json = if contacts.any?
            contacts.map { |c| {name: c.name, phone: c.phone, is_primary: c.is_primary?} }
          else
            [{name: d.contact_name, phone: d.contact_phone, is_primary: true}].select { |c| c[:name].present? || c[:phone].present? }
          end

          items_json = d.items_visible_in_plan.reject(&:cancelled?).map do |item|
            {
              product: item.product,
              quantity: item.quantity,
              notes: item.notes,
              order_item_notes: item.order_item.notes
            }
          end

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
              order_number: order&.number,
              client_name: order&.client&.name,
              seller_code: order&.seller&.seller_code,
              vendor_name: (d.internal_delivery? ? addr&.matching_vendor&.name : nil),
              contact_name: d.contact_name,
              contact_phone: d.contact_phone,
              contacts: contacts_json,
              delivery_notes: d.delivery_notes,
              delivery_date: d.delivery_date&.iso8601,
              delivery_time_preference: d.delivery_time_preference,
              condominio_number: d.condominio_number,
              casa_number: d.casa_number,
              tracking_url: d.public_tracking_url,
              items: items_json,
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
