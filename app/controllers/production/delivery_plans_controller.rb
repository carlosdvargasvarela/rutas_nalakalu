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

  # Bitácora de carga de un plan específico
  def loading
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :loading?

    @assignments = @delivery_plan.delivery_plan_assignments
      .includes(
        delivery: [
          :delivery_address,
          {order: [:client, :seller]},
          {delivery_items: :order_item}
        ]
      )
      .order(:stop_order)

    # Filtros
    @filter_load_status = params[:load_status]
    @filter_search = params[:search]
    @view_mode = params[:view_mode] || "by_delivery" # by_delivery o by_product

    # Aplicar filtros si existen
    if @filter_load_status.present?
      @assignments = @assignments.joins(:delivery).where(deliveries: {load_status: @filter_load_status})
    end

    if @filter_search.present?
      @assignments = @assignments.joins(delivery: {order: :client})
        .where("clients.name ILIKE ? OR orders.number ILIKE ?", "%#{@filter_search}%", "%#{@filter_search}%")
    end

    @load_stats = @delivery_plan.load_stats

    respond_to do |format|
      format.html
      format.json { render json: {plan: @delivery_plan, assignments: @assignments, stats: @load_stats} }
    end
  end

  # Marcar todo el plan como cargado
  def mark_all_loaded
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan, :mark_all_loaded?

    @delivery_plan.mark_all_loaded!
    @load_stats = @delivery_plan.load_stats

    respond_to do |format|
      format.html do
        redirect_to loading_production_delivery_plan_path(@delivery_plan),
          notice: "✅ Todos los productos del plan han sido marcados como cargados."
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("plan_header", partial: "production/delivery_plans/plan_header", locals: {delivery_plan: @delivery_plan, load_stats: @load_stats}),
          turbo_stream.replace("load_summary", partial: "production/delivery_plans/load_summary", locals: {delivery_plan: @delivery_plan, load_stats: @load_stats})
        ]
      end
      format.json { render json: {success: true, stats: @load_stats} }
    end
  end
end
