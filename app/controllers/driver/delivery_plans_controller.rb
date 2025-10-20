# app/controllers/driver/delivery_plans_controller.rb
module Driver
  class DeliveryPlansController < ApplicationController
    before_action :authenticate_user!
    before_action :set_delivery_plan, only: [ :show, :start, :finish, :abort, :update_position_batch ]

    after_action :verify_authorized

    def index
      authorize DeliveryPlan, policy_class: Driver::DeliveryPlanPolicy

      @q = DeliveryPlan.ransack(params[:q])

      @delivery_plans = @q.result.preload(:driver, :deliveries)
                            .left_joins(:deliveries)
                            .select("delivery_plans.*, MIN(deliveries.delivery_date) AS first_delivery_date")
                            .group("delivery_plans.id")
                            .order("MIN(deliveries.delivery_date) DESC")

      respond_to do |format|
        format.html
        format.json { render json: @delivery_plans }
      end
    end

    def show
      authorize [ :driver, @delivery_plan ]

      @assignments = @delivery_plan.delivery_plan_assignments
                                  .includes(delivery: [ :order, :delivery_address, order: :client ])
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
          format.json { render json: { ok: true, status: @delivery_plan.status }, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo iniciar el plan" }
          format.json { render json: { ok: false, error: "No se pudo iniciar" }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: { ok: false, error: "Plan was modified, please reload" }, status: :conflict }
      end
    end

    def finish
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy
      if @delivery_plan.finish!
        respond_to do |format|
          format.html { redirect_to driver_delivery_plans_path, notice: "Plan completado" }
          format.json { render json: { ok: true, status: @delivery_plan.status }, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo completar el plan" }
          format.json { render json: { ok: false, error: "No se pudo completar" }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: { ok: false, error: "Plan was modified, please reload" }, status: :conflict }
      end
    end

    def abort
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy
      if @delivery_plan.abort!
        respond_to do |format|
          format.html { redirect_to driver_delivery_plans_path, notice: "Plan abortado" }
          format.json { render json: { ok: true, status: @delivery_plan.status }, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "No se pudo abortar el plan" }
          format.json { render json: { ok: false, error: "No se pudo abortar" }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::StaleObjectError
      respond_to do |format|
        format.html { redirect_to driver_delivery_plan_path(@delivery_plan), alert: "El plan fue modificado, recarga la página" }
        format.json { render json: { ok: false, error: "Plan was modified, please reload" }, status: :conflict }
      end
    end

    def update_position_batch
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy

      # 🔒 Rechazar si el plan ya está completado o abortado
      if @delivery_plan.completed? || @delivery_plan.aborted?
        render json: { ok: false, error: "Plan already finished" }, status: :forbidden
        return
      end

      positions = position_batch_params[:positions] || []
      if positions.empty?
        render json: { ok: false, error: "No positions provided" }, status: :unprocessable_entity
        return
      end

      valid_positions = positions.select do |pos|
        pos[:lat].present? && pos[:lng].present? &&
          pos[:lat].to_f.between?(-90, 90) &&
          pos[:lng].to_f.between?(-180, 180)
      end

      if valid_positions.empty?
        render json: { ok: false, error: "No valid positions" }, status: :unprocessable_entity
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
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::StaleObjectError
      render json: { ok: false, error: "Plan was modified, please reload" }, status: :conflict
    end

    private

    def set_delivery_plan
      @delivery_plan = DeliveryPlan.find(params[:id])
    end

    def position_batch_params
      params.permit(positions: [ :lat, :lng, :speed, :heading, :accuracy, :at ])
    end
  end
end
