# app/controllers/production/deliveries_controller.rb

class Production::DeliveriesController < ApplicationController
  before_action :authenticate_user!
  include Pundit::Authorization

  before_action :set_delivery, only: %i[
    show edit update approve quick_update add_product
    mark_all_loaded reset_load_status confirm_all_items
    reschedule_delivery reschedule_item mark_item_delivered cancel_item
  ]

  def management
    authorize Delivery, :management?
    @filter = params[:filter] || "this_week"
    @deliveries = filtered_deliveries.page(params[:page]).per(20)
    @stats = {
      pending_approval: pending_approval_count,
      this_week: this_week_count,
      with_errors: deliveries_with_errors_count,
      ready_to_deliver: ready_to_deliver_count
    }
  end

  def show
    authorize @delivery, :show?
    @delivery_history = @delivery.order.deliveries.order(:delivery_date)
    @future_deliveries = @delivery.order.deliveries
      .where("delivery_date > ?", @delivery.delivery_date)
      .order(:delivery_date)
    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.to_a
    @error_detector = Deliveries::ErrorDetector.new(@delivery)
    @has_errors = @error_detector.has_errors?
    @errors = @error_detector.errors if @has_errors
  end

  def edit
    authorize @delivery, :edit?
    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.to_a
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def update
    authorize @delivery, :update?
    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.to_a

    @delivery = Deliveries::Updater.new(
      delivery: @delivery,
      params: params,
      current_user: current_user
    ).call

    respond_to do |format|
      format.html { redirect_to production_delivery_path(@delivery), notice: "✅ Entrega actualizada correctamente" }
      format.turbo_stream { redirect_to production_delivery_path(@delivery), notice: "✅ Entrega actualizada correctamente" }
    end
  rescue => e
    @order = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.to_a

    respond_to do |format|
      format.html { render :edit, status: :unprocessable_entity }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_edit_form_#{@delivery.id}",
          partial: "production/deliveries/edit_form",
          locals: {delivery: @delivery, addresses: @addresses, client: @client}
        ), status: :unprocessable_entity
      end
    end
  end

  def approve
    authorize @delivery, :approve?
    @delivery.update!(approved: true, status: :ready_to_deliver)
    respond_to do |format|
      format.html { redirect_back fallback_location: management_production_deliveries_path, notice: "✅ Entrega aprobada y lista para planificar" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_card_#{@delivery.id}",
          partial: "production/deliveries/management_card",
          locals: {delivery: @delivery}
        )
      end
    end
  end

  def confirm_all_items
    authorize @delivery, :quick_update?
    @delivery.delivery_items.each do |item|
      item.update!(status: :confirmed) if item.respond_to?(:confirmed)
    end
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), notice: "✅ Todos los productos confirmados" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_items_#{@delivery.id}",
          partial: "production/deliveries/delivery_items_list",
          locals: {delivery: @delivery.reload}
        )
      end
    end
  end

  def reschedule_delivery
    authorize @delivery, :quick_update?
    new_date = params[:new_date]
    if new_date.blank?
      redirect_back fallback_location: production_delivery_path(@delivery), alert: "❌ Debes indicar una nueva fecha"
      return
    end
    if @delivery.update(delivery_date: new_date, status: :rescheduled)
      new_delivery = @delivery.dup
      new_delivery.delivery_date = new_date
      new_delivery.status = :scheduled
      new_delivery.approved = false
      new_delivery.save!
      @delivery.delivery_items.each do |item|
        new_delivery.delivery_items.create!(
          order_item: item.order_item,
          quantity_delivered: item.quantity_delivered,
          status: :pending,
          notes: item.notes
        )
      end
      redirect_back fallback_location: production_delivery_path(@delivery),
        notice: "🔄 Entrega reagendada para #{l(new_delivery.delivery_date, format: :long)}"
    else
      redirect_back fallback_location: production_delivery_path(@delivery),
        alert: "❌ Error al reagendar: #{@delivery.errors.full_messages.join(", ")}"
    end
  end

  def reschedule_item
    authorize @delivery, :quick_update?
    item = @delivery.delivery_items.find(params[:item_id])
    new_date = params[:new_date]
    if new_date.blank?
      redirect_back fallback_location: production_delivery_path(@delivery), alert: "❌ Debes indicar una nueva fecha para el item"
      return
    end
    item.update!(status: :rescheduled)
    new_delivery = Delivery.create!(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      delivery_date: new_date,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      delivery_notes: @delivery.delivery_notes,
      delivery_time_preference: @delivery.delivery_time_preference,
      status: :scheduled,
      approved: false
    )
    new_delivery.delivery_items.create!(
      order_item: item.order_item,
      quantity_delivered: item.quantity_delivered,
      status: :pending,
      notes: item.notes
    )
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), notice: "🔄 Producto reagendado para #{l(new_delivery.delivery_date, format: :long)}" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_items_#{@delivery.id}",
          partial: "production/deliveries/delivery_items_list",
          locals: {delivery: @delivery.reload}
        )
      end
    end
  end

  def mark_item_delivered
    authorize @delivery, :quick_update?
    item = @delivery.delivery_items.find(params[:item_id])
    item.update!(status: :delivered)
    @delivery.update!(status: :delivered) if @delivery.delivery_items.reload.all? { |i| i.status.to_s == "delivered" }
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), notice: "✅ Producto marcado como entregado" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_items_#{@delivery.id}",
          partial: "production/deliveries/delivery_items_list",
          locals: {delivery: @delivery.reload}
        )
      end
    end
  end

  def cancel_item
    authorize @delivery, :quick_update?
    item = @delivery.delivery_items.find(params[:item_id])
    item.update!(status: :cancelled)
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), notice: "🚫 Producto cancelado" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_items_#{@delivery.id}",
          partial: "production/deliveries/delivery_items_list",
          locals: {delivery: @delivery.reload}
        )
      end
    end
  end

  def quick_update
    authorize @delivery, :quick_update?
    if @delivery.update(quick_update_params)
      respond_to do |format|
        format.html { redirect_back fallback_location: management_production_deliveries_path, notice: "✅ Entrega actualizada correctamente" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "delivery_card_#{@delivery.id}",
            partial: "production/deliveries/management_card",
            locals: {delivery: @delivery}
          )
        end
      end
    else
      redirect_back fallback_location: management_production_deliveries_path,
        alert: "❌ Error: #{@delivery.errors.full_messages.join(", ")}"
    end
  end

  def add_product
    authorize @delivery, :add_product?
    ActiveRecord::Base.transaction do
      order_item = @delivery.order.order_items.create!(
        product: params[:product],
        quantity: params[:quantity].to_i,
        notes: params[:notes],
        status: :in_production
      )
      @delivery.delivery_items.create!(
        order_item: order_item,
        quantity_delivered: params[:quantity_delivered]&.to_i || params[:quantity].to_i,
        status: :pending
      )
    end
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), notice: "✅ Producto agregado exitosamente" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "delivery_items_#{@delivery.id}",
          partial: "production/deliveries/delivery_items_list",
          locals: {delivery: @delivery.reload}
        )
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_path(@delivery), alert: "❌ Error al agregar producto: #{e.message}" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "delivery_items_#{@delivery.id}",
          html: "<div class='alert alert-danger m-3'>❌ #{e.message}</div>"
        )
      end
    end
  end

  def mark_all_loaded
    authorize @delivery, :mark_all_loaded?
    @delivery.mark_all_loaded!
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_plans_path, notice: "✅ Todos los productos marcados como cargados." }
      format.turbo_stream { render_delivery_update_streams }
    end
  end

  def reset_load_status
    authorize @delivery, :reset_load_status?
    @delivery.reset_load_status!
    respond_to do |format|
      format.html { redirect_back fallback_location: production_delivery_plans_path, notice: "🔄 Estado de carga reseteado." }
      format.turbo_stream { render_delivery_update_streams }
    end
  end

  private

  def set_delivery
    @delivery = Delivery.includes(
      order: [:client, :seller, :order_items],
      delivery_address: :client,
      delivery_items: :order_item
    ).find(params[:id])
  end

  def filtered_deliveries
    base = Delivery.includes(order: [:client, :seller], delivery_address: :client)
    case @filter
    when "pending_approval" then base.where(approved: false, delivery_date: current_week_range)
    when "this_week" then base.where(delivery_date: current_week_range)
    when "errors" then detect_deliveries_with_errors
    when "ready" then base.where(status: :ready_to_deliver)
    else base.where(delivery_date: current_week_range)
    end.order(:delivery_date, :id)
  end

  def detect_deliveries_with_errors
    date_range = Date.current..Date.current.next_week.end_of_week
    candidates = Delivery.where(delivery_date: date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .includes(order: [:client, :seller, :order_items], delivery_address: :client, delivery_items: :order_item)
      .limit(100)
    ids = candidates.select { |d| Deliveries::ErrorDetector.new(d).has_errors? }.map(&:id)
    Delivery.where(id: ids).includes(order: [:client, :seller], delivery_address: :client)
  end

  def pending_approval_count = Delivery.where(approved: false, delivery_date: current_week_range).count
  def this_week_count = Delivery.where(delivery_date: current_week_range).count
  def ready_to_deliver_count = Delivery.where(status: :ready_to_deliver).count

  def deliveries_with_errors_count
    date_range = Date.current..Date.current.next_week.end_of_week
    Delivery.where(delivery_date: date_range)
      .where(status: [:scheduled, :ready_to_deliver])
      .includes(order: :order_items, delivery_items: :order_item)
      .limit(100)
      .count { |d| Deliveries::ErrorDetector.new(d).has_errors? }
  end

  def current_week_range = Date.current.beginning_of_week..Date.current.end_of_week

  def quick_update_params
    params.require(:delivery).permit(:delivery_date, :contact_name, :contact_phone, :delivery_notes, :delivery_time_preference)
  end

  def delivery_params
    params.require(:delivery).permit(
      :delivery_date, :delivery_time_preference, :contact_name,
      :contact_phone, :delivery_notes, :delivery_address_id,
      delivery_items_attributes: [:id, :quantity_delivered, :status, :notes, :_destroy,
        order_item_attributes: [:id, :product, :quantity, :notes]]
    )
  end

  def render_delivery_update_streams
    @delivery_plan = @delivery.delivery_plan
    @load_stats = @delivery_plan.load_stats if @delivery_plan
    @assignment = @delivery.delivery_plan_assignment
    streams = [turbo_stream.replace("delivery_#{@delivery.id}", partial: "production/deliveries/delivery_card", locals: {delivery: @delivery, assignment: @assignment})]
    if @delivery_plan
      streams << turbo_stream.replace("plan_header", partial: "production/delivery_plans/plan_header", locals: {delivery_plan: @delivery_plan, load_stats: @load_stats})
      streams << turbo_stream.replace("load_summary", partial: "production/delivery_plans/load_summary", locals: {delivery_plan: @delivery_plan, load_stats: @load_stats})
    end
    render turbo_stream: streams
  end
end
