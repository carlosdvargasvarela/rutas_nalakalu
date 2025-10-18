# app/controllers/driver/delivery_plans_controller.rb
module Driver
  class DeliveryPlansController < ApplicationController
    before_action :authenticate_user!
    # Incluye aquí SOLO acciones que existen abajo en este mismo controller
    before_action :set_delivery_plan, only: [ :show, :start, :finish, :abort, :update_position, :update_position_batch ]

    after_action :verify_authorized

    def index
      authorize DeliveryPlan, policy_class: Driver::DeliveryPlanPolicy

      base_scope = policy_scope(DeliveryPlan, policy_scope_class: Driver::DeliveryPlanPolicy::Scope)
                    .includes(:driver)
                    .order(created_at: :desc)

      @q = base_scope.ransack(params[:q])
      @q.status_in = %w[routes_created in_progress] if params[:q].blank?
      @delivery_plans = @q.result

      respond_to do |format|
        format.html
        format.json { render json: @delivery_plans }
      end
    end

    def show
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy

      @assignments = @delivery_plan.delivery_plan_assignments
                                   .includes(delivery: [ :delivery_items ])
                                   .ordered

      respond_to do |format|
        format.html
        format.json do
          render json: {
            id: @delivery_plan.id,
            status: @delivery_plan.status,
            progress: @delivery_plan.progress,
            assignments: @assignments.map { |a|
              {
                id: a.id,
                status: a.status,
                stop_order: a.stop_order,
                delivery: {
                  id: a.delivery.id,
                  address: a.delivery.customer.address
                }
              }
            }
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

    def update_position
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy

      @delivery_plan.update!(
        current_latitude: position_params[:latitude],
        current_longitude: position_params[:longitude],
        current_speed: position_params[:speed],
        current_heading: position_params[:heading],
        current_accuracy: position_params[:accuracy],
        last_seen_at: position_params[:timestamp] || Time.current
      )

      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::StaleObjectError
      render json: { ok: false, error: "Plan was modified, please reload" }, status: :conflict
    end

    def update_position_batch
      authorize @delivery_plan, policy_class: Driver::DeliveryPlanPolicy

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
        current_latitude: last_position[:lat],
        current_longitude: last_position[:lng],
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

    def position_params
      params.permit(:latitude, :longitude, :speed, :heading, :accuracy, :timestamp)
    end

    def position_batch_params
      params.permit(positions: [ :lat, :lng, :speed, :heading, :accuracy, :at ])
    end
  end
end
