class Production::DeliveryItemsController < ApplicationController
  before_action :authenticate_user!
  include Pundit::Authorization

  before_action :set_delivery_item

  def mark_loaded
    authorize @delivery_item, :mark_loaded?
    @delivery_item.mark_loaded!

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "✅ Producto marcado como cargado." }
      format.turbo_stream { render_item_update_streams }
      format.json { render json: {success: true, item: @delivery_item} }
    end
  end

  def mark_unloaded
    authorize @delivery_item, :mark_unloaded?
    @delivery_item.mark_unloaded!

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "🔄 Producto marcado como no cargado." }
      format.turbo_stream { render_item_update_streams }
      format.json { render json: {success: true, item: @delivery_item} }
    end
  end

  def mark_missing
    authorize @delivery_item, :mark_missing?
    @delivery_item.mark_missing!

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "⚠️ Producto marcado como faltante." }
      format.turbo_stream { render_item_update_streams }
      format.json { render json: {success: true, item: @delivery_item} }
    end
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def render_item_update_streams
    @delivery = @delivery_item.delivery
    @delivery_plan = @delivery.delivery_plan
    @load_stats = @delivery_plan.load_stats if @delivery_plan
    @assignment = @delivery.delivery_plan_assignments.first

    streams = []

    # Fila del item
    streams << turbo_stream.replace(
      "delivery_item_#{@delivery_item.id}",
      partial: "production/delivery_items/delivery_item_row",
      locals: {item: @delivery_item}
    )

    # Tarjeta de la entrega (incluye su %)
    streams << turbo_stream.replace(
      "delivery_#{@delivery.id}",
      partial: "production/deliveries/delivery_card",
      locals: {delivery: @delivery, assignment: @assignment}
    )

    if @delivery_plan
      # Header del plan (barra de progreso grande)
      streams << turbo_stream.replace(
        "plan_header",
        partial: "production/delivery_plans/plan_header",
        locals: {delivery_plan: @delivery_plan, load_stats: @load_stats}
      )

      # Resumen de carga (totales cargados, sin cargar, faltantes)
      streams << turbo_stream.replace(
        "load_summary",
        partial: "production/delivery_plans/load_summary",
        locals: {delivery_plan: @delivery_plan, load_stats: @load_stats}
      )
    end

    render turbo_stream: streams
  end
end
