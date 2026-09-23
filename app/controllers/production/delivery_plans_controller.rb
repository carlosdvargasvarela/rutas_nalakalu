# app/controllers/production/delivery_plans_controller.rb
class Production::DeliveryPlansController < ApplicationController
  before_action :authenticate_user!
  include Pundit::Authorization

  # Lista de planes del día (modo despacho)
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.current

    # Obtener todos los planes que tienen entregas en la fecha seleccionada
    @delivery_plans = policy_scope(DeliveryPlan)
      .joins(:deliveries)
      .where(deliveries: {delivery_date: @date})
      .distinct
      .includes(:driver, deliveries: [:delivery_items, :delivery_address, order: :client])
      .order(:truck, :driver_id)

    authorize DeliveryPlan

    respond_to do |format|
      format.html
      format.json { render json: @delivery_plans.as_json(include: :load_stats) }
    end
  end

  # Bitácora de carga: paradas del camión en orden de carga (izquierda) y
  # productos de la parada abierta (derecha).
  def loading
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :loading?

    @filter = (params[:filter] == "pending") ? "pending" : "all"
    @assignments = @delivery_plan.loading_assignments.includes(stop_includes)
    @assignments = @assignments.joins(:delivery).where.not(deliveries: {load_status: Delivery.load_statuses[:all_loaded]}) if @filter == "pending"
    @assignments = @assignments.to_a

    # En celular solo se ve la lista hasta que se elige una parada (params[:stop]);
    # en tablet/PC siempre hay una abierta: la elegida o la primera pendiente.
    @stop_chosen = params[:stop].present?
    @selected = @assignments.find { |a| a.delivery_id == params[:stop].to_i } ||
      @assignments.find { |a| !a.delivery.load_all_loaded? } || @assignments.first
    @load_stats = @delivery_plan.load_stats
  end

  # Hoja imprimible del camión: paradas en orden de carga con sus productos.
  def checklist
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :checklist?
    @assignments = @delivery_plan.loading_assignments.includes(stop_includes)
  end

  # Marcar todo el plan como cargado
  def mark_all_loaded
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :mark_all_loaded?
    return redirect_to(loading_path_for(@delivery_plan), alert: "La carga ya está cerrada.") if @delivery_plan.load_closed?

    @delivery_plan.mark_all_loaded!
    redirect_to loading_path_for(@delivery_plan), notice: "Todos los productos del plan fueron marcados como cargados."
  end

  def close_load
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :close_load?
    @delivery_plan.close_load!(current_user) unless @delivery_plan.load_closed?
    redirect_to loading_path_for(@delivery_plan), notice: "Carga cerrada."
  end

  def reopen_load
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :reopen_load?
    @delivery_plan.reopen_load!(current_user) if @delivery_plan.load_closed?
    redirect_to loading_path_for(@delivery_plan), notice: "Carga reabierta."
  end

  private

  def stop_includes
    {delivery: [:delivery_address, {order: [:client, :seller]}, {delivery_items: :order_item}]}
  end

  def loading_path_for(plan)
    loading_production_delivery_plan_path(plan, stop: params[:stop].presence)
  end
end
