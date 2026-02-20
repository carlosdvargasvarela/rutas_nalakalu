# app/controllers/production/deliveries_controller.rb

class Production::DeliveriesController < ApplicationController
  before_action :authenticate_user!
  include Pundit::Authorization

  before_action :set_delivery, only: [
    :mark_all_loaded,
    :reset_load_status,
    :approve,
    :quick_update,
    :add_product,
    :show
  ]

  # =============================================================================
  # VISTA DE GESTIÓN OPERATIVA
  # =============================================================================

  def management
    authorize Delivery, :management?

    @filter = params[:filter] || "this_week"
    @deliveries = filtered_deliveries.page(params[:page]).per(20)

    # Estadísticas rápidas
    @stats = {
      pending_approval: pending_approval_count,
      this_week: this_week_count,
      with_errors: deliveries_with_errors_count,
      ready_to_deliver: ready_to_deliver_count
    }
  end

  # =============================================================================
  # VISTA DE DETALLE DE ENTREGA
  # =============================================================================

  def show
    authorize @delivery, :show?

    @delivery_history = @delivery.order.deliveries.order(:delivery_date)
    @future_deliveries = @delivery.order.deliveries
      .where("delivery_date > ?", @delivery.delivery_date)
      .order(:delivery_date)

    @error_detector = Deliveries::ErrorDetector.new(@delivery)
    @has_errors = @error_detector.has_errors?
    @errors = @error_detector.errors if @has_errors
  end

  # =============================================================================
  # ACCIONES DE GESTIÓN
  # =============================================================================

  def approve
    authorize @delivery, :approve?

    @delivery.update!(approved: true, status: :ready_to_deliver)

    respond_to do |format|
      format.html do
        redirect_back fallback_location: management_production_deliveries_path,
          notice: "✅ Entrega aprobada y lista para planificar"
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_card_#{@delivery.id}",
          partial: "production/deliveries/management_card",
          locals: {delivery: @delivery}
        )
      end
      format.json { render json: {success: true, delivery: @delivery} }
    end
  end

  def quick_update
    authorize @delivery, :quick_update?

    if @delivery.update(quick_update_params)
      respond_to do |format|
        format.html do
          redirect_back fallback_location: management_production_deliveries_path,
            notice: "✅ Entrega actualizada correctamente"
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "delivery_card_#{@delivery.id}",
            partial: "production/deliveries/management_card",
            locals: {delivery: @delivery}
          )
        end
        format.json { render json: {success: true, message: "Entrega actualizada"} }
      end
    else
      respond_to do |format|
        format.html do
          redirect_back fallback_location: management_production_deliveries_path,
            alert: "❌ Error: #{@delivery.errors.full_messages.join(", ")}"
        end
        format.json do
          render json: {success: false, errors: @delivery.errors.full_messages},
            status: :unprocessable_entity
        end
      end
    end
  end

  def add_product
    authorize @delivery, :add_product?

    begin
      ActiveRecord::Base.transaction do
        # Crear OrderItem
        order_item = @delivery.order.order_items.create!(
          product: params[:product],
          quantity: params[:quantity].to_i,
          notes: params[:notes]
        )

        # Crear DeliveryItem asociado
        @delivery.delivery_items.create!(
          order_item: order_item,
          quantity_delivered: params[:quantity_delivered]&.to_i || params[:quantity].to_i,
          status: :pending
        )
      end

      respond_to do |format|
        format.html do
          redirect_back fallback_location: production_delivery_path(@delivery),
            notice: "✅ Producto agregado exitosamente"
        end
        format.turbo_stream do
          @delivery.reload
          # ✅ CORRECCIÓN: Solo reemplazar la lista de items, sin flash
          render turbo_stream: turbo_stream.replace(
            "delivery_items_#{@delivery.id}",
            partial: "production/deliveries/delivery_items_list",
            locals: {delivery: @delivery}
          )
        end
        format.json { render json: {success: true, delivery: @delivery.reload} }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html do
          redirect_back fallback_location: production_delivery_path(@delivery),
            alert: "❌ Error al agregar producto: #{e.message}"
        end
        format.turbo_stream do
          # ✅ CORRECCIÓN: Renderizar un mensaje de error simple
          render turbo_stream: turbo_stream.update(
            "delivery_items_#{@delivery.id}",
            html: "<div class='alert alert-danger'>❌ #{e.message}</div>"
          )
        end
        format.json do
          render json: {success: false, error: e.message},
            status: :unprocessable_entity
        end
      end
    end
  end

  # =============================================================================
  # ACCIONES DE CARGA (LOADING)
  # =============================================================================

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

  # =============================================================================
  # MÉTODOS PRIVADOS
  # =============================================================================

  private

  def set_delivery
    @delivery = Delivery.includes(
      order: [:client, :seller, :order_items],
      delivery_address: :client,
      delivery_items: :order_item
    ).find(params[:id])
  end

  # ---------------------------------------------------------------------------
  # Filtros para vista de gestión
  # ---------------------------------------------------------------------------

  def filtered_deliveries
    base = Delivery.includes(
      order: [:client, :seller],
      delivery_address: :client
    )

    case @filter
    when "pending_approval"
      base.where(approved: false, delivery_date: current_week_range)
    when "this_week"
      base.where(delivery_date: current_week_range)
    when "errors"
      detect_deliveries_with_errors
    when "ready"
      base.where(status: :ready_to_deliver)
    else
      base.where(delivery_date: current_week_range)
    end.order(:delivery_date, :id)
  end

  def detect_deliveries_with_errors
    date_range = Date.current..Date.current.next_week.end_of_week

    candidates = Delivery.where(delivery_date: date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .includes(
        order: [:client, :seller, :order_items],
        delivery_address: :client,
        delivery_items: :order_item
      )
      .limit(100)

    ids_with_errors = candidates.select do |delivery|
      Deliveries::ErrorDetector.new(delivery).has_errors?
    end.map(&:id)

    Delivery.where(id: ids_with_errors)
      .includes(order: [:client, :seller], delivery_address: :client)
  end

  # ---------------------------------------------------------------------------
  # Contadores para estadísticas
  # ---------------------------------------------------------------------------

  def pending_approval_count
    Delivery.where(
      approved: false,
      delivery_date: current_week_range
    ).count
  end

  def this_week_count
    Delivery.where(delivery_date: current_week_range).count
  end

  def deliveries_with_errors_count
    date_range = Date.current..Date.current.next_week.end_of_week

    candidates = Delivery.where(delivery_date: date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .limit(100)

    candidates.count { |d| Deliveries::ErrorDetector.new(d).has_errors? }
  end

  def ready_to_deliver_count
    Delivery.where(status: :ready_to_deliver).count
  end

  def current_week_range
    Date.current.beginning_of_week..Date.current.end_of_week
  end

  # ---------------------------------------------------------------------------
  # Parámetros permitidos
  # ---------------------------------------------------------------------------

  def quick_update_params
    params.require(:delivery).permit(
      :delivery_date,
      :contact_name,
      :contact_phone,
      :delivery_notes,
      :delivery_time_preference
    )
  end

  # ---------------------------------------------------------------------------
  # Turbo Streams para carga
  # ---------------------------------------------------------------------------

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
