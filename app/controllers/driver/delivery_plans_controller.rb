# app/controllers/driver/delivery_plans_controller.rb
module Driver
  class DeliveryPlansController < ApplicationController
    before_action :authenticate_user!
    before_action :set_delivery_plan, only: [:show, :start, :finish, :abort, :update_position_batch]

    after_action :verify_authorized

    def index
      authorize DeliveryPlan, policy_class: Driver::DeliveryPlanPolicy

      # Base: SOLO planes del conductor actual (muy importante)
      base_scope = DeliveryPlan.where(driver_id: current_user.id)

      # Extraemos filtros de fecha (no los dejamos en Ransack porque first_delivery_date es alias)
      q_params = (params[:q] || {}).to_h

      from = q_params.delete("first_delivery_date_gteq").presence
      to = q_params.delete("first_delivery_date_lteq").presence

      # Ransack SOLO para columnas reales del modelo
      @q = base_scope.ransack(q_params)

      delivered_status = Delivery.statuses[:delivered]

      scope = @q.result
        .left_joins(:deliveries)
        .select(<<~SQL)
          delivery_plans.*,
          MIN(deliveries.delivery_date) AS first_delivery_date,
          MAX(deliveries.delivery_date) AS last_delivery_date,
          COUNT(deliveries.id)          AS deliveries_count,
          COUNT(
            CASE WHEN deliveries.status = #{delivered_status} THEN 1 END
          ) AS delivered_count
        SQL
        .group("delivery_plans.id")

      # Filtro de fechas sobre deliveries.delivery_date (no sobre el alias)
      if from
        scope = scope.where("deliveries.delivery_date >= ?", Date.parse(from))
      end

      if to
        scope = scope.where("deliveries.delivery_date <= ?", Date.parse(to))
      end

      # Orden estable: más recientes arriba (por última entrega), fallback por creación
      scope = scope.order(Arel.sql("MAX(deliveries.delivery_date) DESC NULLS LAST, delivery_plans.created_at DESC"))

      # Stats globales (antes de paginar)
      all_plans = scope.to_a
      @stats = {
        total_plans: all_plans.size,
        total_deliveries: all_plans.sum { |p| p.deliveries_count.to_i },
        by_status: all_plans.group_by(&:status).transform_values(&:size)
      }

      # Paginación (mobile-first)
      @delivery_plans = Kaminari.paginate_array(all_plans)
        .page(params[:page])
        .per(10)

      respond_to do |format|
        format.html
        format.json { render json: @delivery_plans }
      end
    rescue ArgumentError
      # Si Date.parse falla por algún valor raro
      redirect_to driver_delivery_plans_path, alert: "Filtros de fecha inválidos"
    end

    def show
      authorize [:driver, @delivery_plan]

      @assignments = @delivery_plan.delivery_plan_assignments
        .includes(delivery: [:order, :delivery_address, {order: :client}])
        .order(:stop_order)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            id: @delivery_plan.id,
            current_lat: @delivery_plan.current_lat,
            current_lng: @delivery_plan.current_lng,
            last_seen_at: @delivery_plan.last_seen_at,
            status: @delivery_plan.status,
            assignments: @assignments.map do |a|
              {
                id: a.id,
                stop_order: a.stop_order,
                status: a.status,
                delivery: {
                  id: a.delivery.id,
                  latitude: a.delivery.delivery_address.latitude,
                  longitude: a.delivery.delivery_address.longitude,
                  contact_name: a.delivery.contact_name,
                  contact_phone: a.delivery.contact_phone
                }
              }
            end
          }
        end
      end
    end

    def start
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy
      if @delivery_plan.start!
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), notice: "Plan iniciado" }
          format.json { render json: {ok: true, status: @delivery_plan.status}, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo iniciar el plan" }
          format.json { render json: {ok: false, error: "No se pudo iniciar"}, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: {ok: false, error: "Plan was modified, please reload"}, status: :conflict }
      end
    end

    def finish
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy
      if @delivery_plan.finish!
        respond_to do |format|
          format.html { redirect_to driver_delivery_plans_path, notice: "Plan completado" }
          format.json { render json: {ok: true, status: @delivery_plan.status}, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo completar el plan" }
          format.json { render json: {ok: false, error: "No se pudo completar"}, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: {ok: false, error: "Plan was modified, please reload"}, status: :conflict }
      end
    end

    def abort
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy
      if @delivery_plan.abort!
        respond_to do |format|
          format.html { redirect_to driver_delivery_plans_path, notice: "Plan abortado" }
          format.json { render json: {ok: true, status: @delivery_plan.status}, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo abortar el plan" }
          format.json { render json: {ok: false, error: "No se pudo abortar"}, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: {ok: false, error: "Plan was modified, please reload"}, status: :conflict }
      end
    end

    def update_position_batch
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy

      if @delivery_plan.completed? || @delivery_plan.aborted?
        render json: {ok: false, error: "Plan already finished"}, status: :forbidden
        return
      end

      positions = position_batch_params[:positions] || []
      if positions.empty?
        render json: {ok: false, error: "No positions provided"}, status: :unprocessable_entity
        return
      end

      valid_positions = positions.select do |pos|
        pos[:lat].present? && pos[:lng].present? &&
          pos[:lat].to_f.between?(-90, 90) &&
          pos[:lng].to_f.between?(-180, 180)
      end

      if valid_positions.empty?
        render json: {ok: false, error: "No valid positions"}, status: :unprocessable_entity
        return
      end

      last_position = valid_positions.max_by { |p| p[:at]&.to_time || Time.current }
      @delivery_plan.update!(
        current_lat: last_position[:lat],
        current_lng: last_position[:lng],
        current_speed: last_position[:speed],
        current_heading: last_position[:heading],
        current_accuracy: last_position[:accuracy],
        last_seen_at: last_position[:at]&.to_time || Time.current
      )

      DeliveryPlanLocation.create_from_batch(@delivery_plan, valid_positions)

      render json: {
        ok: true,
        accepted: valid_positions.size,
        rejected: positions.size - valid_positions.size
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: {ok: false, error: e.message}, status: :unprocessable_entity
    rescue ActiveRecord::StaleObjectError
      render json: {ok: false, error: "Plan was modified, please reload"}, status: :conflict
    end

    private

    def set_delivery_plan
      # Extra seguridad: no permitir abrir planes de otros drivers
      @delivery_plan = DeliveryPlan.where(driver_id: current_user.id).find(params[:id])
    end

    def position_batch_params
      params.permit(positions: [:lat, :lng, :speed, :heading, :accuracy, :at])
    end
  end
end
