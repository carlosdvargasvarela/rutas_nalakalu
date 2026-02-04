# app/controllers/driver/delivery_plans_controller.rb
module Driver
  class DeliveryPlansController < ApplicationController
    before_action :authenticate_user!
    before_action :set_delivery_plan, only: [:show, :start, :finish, :abort]

    after_action :verify_authorized

    def index
      authorize DeliveryPlan, policy_class: Driver::DeliveryPlanPolicy

      # Base: TODOS los planes (sin restricción de driver)
      base_scope = DeliveryPlan.all

      # Extraemos filtros de fecha manuales (porque first_delivery_date es un alias SQL)
      q_params = (params[:q] || {}).to_h
      from = q_params.delete("first_delivery_date_gteq").presence
      to = q_params.delete("first_delivery_date_lteq").presence

      @q = base_scope.ransack(q_params)

      delivered_status = Delivery.statuses[:delivered]

      # Query con agregados SQL para performance y precisión
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

      # Aplicar filtros de fecha sobre la tabla de entregas
      if from
        scope = scope.where("deliveries.delivery_date >= ?", Date.parse(from))
      end

      if to
        scope = scope.where("deliveries.delivery_date <= ?", Date.parse(to))
      end

      # Orden: Más recientes primero
      scope = scope.order(Arel.sql("MAX(deliveries.delivery_date) DESC NULLS LAST, delivery_plans.created_at DESC"))

      # Estadísticas globales para el resumen
      all_plans = scope.to_a
      @stats = {
        total_plans: all_plans.size,
        total_deliveries: all_plans.sum { |p| p.deliveries_count.to_i },
        by_status: all_plans.group_by(&:status).transform_values(&:size)
      }

      # Paginación
      @delivery_plans = Kaminari.paginate_array(all_plans)
        .page(params[:page])
        .per(10)

      # Camiones de todos los planes para el filtro
      @available_trucks = DeliveryPlan.distinct.pluck(:truck).compact.sort

      respond_to do |format|
        format.html
        format.json { render json: @delivery_plans }
      end
    rescue ArgumentError
      redirect_to driver_delivery_plans_path, alert: "Formato de fecha inválido"
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
      plan = DeliveryPlan.find(params[:delivery_plan_id])

      authorize plan, :update_position_batch?, policy_class: Driver::DeliveryPlanPolicy

      positions = params[:positions] || []
      saved_count = 0

      positions.each do |pos|
        location = plan.delivery_plan_locations.create(
          latitude: pos[:latitude],
          longitude: pos[:longitude],
          accuracy: pos[:accuracy],
          speed: pos[:speed],
          heading: pos[:heading],
          recorded_at: pos[:timestamp] || Time.current
        )

        saved_count += 1 if location.persisted?
      end

      # 🆕 Actualizar la última posición conocida del plan
      if positions.any?
        last_position = positions.last
        plan.update_columns(
          current_lat: last_position[:latitude],
          current_lng: last_position[:longitude],
          last_seen_at: Time.current
        )
      end

      render json: {
        success: true,
        saved: saved_count,
        total: positions.size
      }
    end

    private

    def set_delivery_plan
      # Sin restricción de driver_id
      @delivery_plan = DeliveryPlan.find(params[:id])
    end

    def position_batch_params
      params.permit(positions: [:lat, :lng, :speed, :heading, :accuracy, :at])
    end
  end
end
