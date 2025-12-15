class Production::DeliveriesController < ApplicationController
  before_action :authenticate_user!
  include Pundit::Authorization

  before_action :set_delivery

  def mark_all_loaded
    authorize @delivery, :mark_all_loaded?
    @delivery.mark_all_loaded!

    respond_to do |format|
      format.html do
        redirect_back fallback_location: production_delivery_plans_path,
          notice: "✅ Todos los productos de la entrega han sido marcados como cargados."
      end
      format.turbo_stream { render_delivery_update_streams }
      format.json { render json: {success: true, delivery: @delivery.as_json(methods: [:load_percentage])} }
    end
  end

  def reset_load_status
    authorize @delivery, :reset_load_status?
    @delivery.reset_load_status!

    respond_to do |format|
      format.html do
        redirect_back fallback_location: production_delivery_plans_path,
          notice: "🔄 El estado de carga de la entrega ha sido reseteado."
      end
      format.turbo_stream { render_delivery_update_streams }
      format.json { render json: {success: true} }
    end
  end

  private

  def set_delivery
    @delivery = Delivery.find(params[:id])
  end

  def render_delivery_update_streams
    @delivery_plan = @delivery.delivery_plan
    @load_stats = @delivery_plan.load_stats if @delivery_plan
    @assignment = @delivery.delivery_plan_assignments.first

    streams = []

    # Reemplazar tarjeta de la entrega
    streams << turbo_stream.replace(
      "delivery_#{@delivery.id}",
      partial: "production/deliveries/delivery_card",
      locals: {delivery: @delivery, assignment: @assignment}
    )

    if @delivery_plan
      # Header del plan
      streams << turbo_stream.replace(
        "plan_header",
        partial: "production/delivery_plans/plan_header",
        locals: {delivery_plan: @delivery_plan, load_stats: @load_stats}
      )

      # Resumen del plan
      streams << turbo_stream.replace(
        "load_summary",
        partial: "production/delivery_plans/load_summary",
        locals: {delivery_plan: @delivery_plan, load_stats: @load_stats}
      )
    end

    render turbo_stream: streams
  end
end
