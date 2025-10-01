# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :set_delivery, only: [ :show, :edit, :update, :mark_as_delivered, :confirm_all_items, :reschedule_all, :approve, :note, :archive ]
  before_action :set_addresses, only: [ :new, :edit, :create, :update ]

  # GET /deliveries
  def index
    session[:deliveries_return_to] = request.fullpath
    base_scope = params[:show_rescheduled] == "1" ? Delivery.all : Delivery.where.not(status: :rescheduled)
    @q = base_scope.ransack(params[:q])
    deliveries_scope = @q.result.includes(order: [ :client, :seller ], delivery_address: :client)

    @deliveries = deliveries_scope.order(delivery_date: :asc).page(params[:page])
    @all_deliveries = deliveries_scope.includes(delivery_items: { order_item: :order }).order(delivery_date: :asc)

    authorize Delivery

    respond_to do |format|
      format.html
      format.xlsx { response.headers["Content-Disposition"] = "attachment; filename=entregas_#{Date.today.strftime('%Y%m%d')}.xlsx" }
      format.csv  { send_data @all_deliveries.to_csv, filename: "entregas_#{Date.today.strftime('%Y%m%d')}.csv" }
    end
  end

  def show
    @future_deliveries = Delivery
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where.not(id: @delivery.id)
      .where(status: [ :scheduled, :ready_to_deliver, :in_plan, :in_route ])

    @delivery_history = @delivery.delivery_history
  end

  def new
    if params[:order_id].present?
      @order = Order.find(params[:order_id])
      @client = @order.client
      @delivery = @order.deliveries.build
      @delivery.build_delivery_address(client: @client)
    else
      @order = Order.new
      @client = Client.new
      @delivery = Delivery.new
      @delivery.build_delivery_address
    end

    @clients = Client.all.order(:name)
    @addresses = (@client&.delivery_addresses || []).to_a
    @orders = (@client&.orders || []).to_a
  end

  def edit
    @client = @delivery.order.client
    @order  = @delivery.order

    @addresses = @client.delivery_addresses.to_a
    @orders = @client.orders.to_a
    @clients = [ @client ]

    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
  end

  # POST /deliveries
  def create
    authorize Delivery
    @delivery = Deliveries::Creator.new(params: params, current_user: current_user).call
    redirect_to @delivery, notice: "Entrega creada correctamente."
  rescue => e
    handle_create_error(e)
  end

  # PATCH/PUT /deliveries/:id
  def update
    authorize @delivery, :edit?
    @delivery = Deliveries::Updater.new(delivery: @delivery, params: params, current_user: current_user).call
    redirect_to @delivery, notice: "Entrega actualizada correctamente."
  rescue => e
    handle_update_error(e)
  end

  def reschedule_all
    authorize @delivery, :edit?
    new_delivery = Deliveries::Rescheduler.new(delivery: @delivery, new_date: safe_date(params[:new_date]), current_user: current_user).call
    redirect_to(session.delete(:deliveries_return_to) || deliveries_path, notice: "Entrega reagendada para el #{I18n.l new_delivery.delivery_date, format: :long}.")
  rescue => e
    redirect_to(session[:deliveries_return_to] || deliveries_path, alert: "Error al reagendar: #{e.message}")
  end

  def create_internal_delivery
    authorize Delivery
    @delivery = Deliveries::InternalCreator.new(params: params, current_user: current_user).call
    redirect_to deliveries_path, notice: "Mandado interno creado correctamente."
  rescue => e
    handle_internal_error(e)
  end

  def create_service_case
    authorize Delivery
    @delivery = Deliveries::ServiceCaseCreator.new(params: params, current_user: current_user).call
    redirect_to deliveries_path, notice: "Caso de servicio creado correctamente."
  rescue => e
    handle_service_case_error(e)
  end

  def create_service_case_for_existing
    parent_delivery = Delivery.find(params[:id])
    authorize parent_delivery, :edit?
    @service_case = Deliveries::ServiceCaseForExistingCreator.new(parent_delivery: parent_delivery, params: params, current_user: current_user).call
    redirect_to delivery_path(@service_case),
      notice: "Se creó un caso de servicio (#{@service_case.display_type}) para el #{I18n.l @service_case.delivery_date, format: :long}."
  rescue => e
    handle_service_case_existing_error(e, parent_delivery)
  end

  def confirm_all_items
    authorize @delivery, :edit?
    updated = @delivery.delivery_items.where(status: :pending).update_all(status: :confirmed, updated_at: Time.current)
    @delivery.update_status_based_on_items
    redirect_to(session.delete(:deliveries_return_to) || delivery_path(@delivery), notice: "#{updated} productos confirmados para entrega.")
  end

  def mark_as_delivered
    @delivery.mark_as_delivered!
    redirect_to @delivery, notice: "Entrega marcada como completada."
  end

  def approve
    authorize @delivery, :approve?
    @delivery.approve!
    redirect_to @delivery, notice: "Entrega aprobada correctamente para esta semana."
  end

  def archive
    if @delivery.update(status: :archived)
      redirect_to @delivery, notice: "🚚 La entrega fue archivada correctamente."
    else
      redirect_to @delivery, alert: "⚠️ No se pudo archivar la entrega."
    end
  end

  def by_week
    session[:deliveries_return_to] = request.fullpath
    @week = (1..53).cover?(params[:week].to_i) ? params[:week].to_i : Date.today.cweek
    @year = params[:year].to_i >= 2000 ? params[:year].to_i : Date.today.cwyear
    start_date = Date.commercial(@year, @week, 1)
    @deliveries = Delivery.for_week(start_date).includes(order: :client, delivery_address: {}, delivery_items: {}).order("deliveries.delivery_date ASC").page(params[:page])
    render :index
  end

  def service_cases
    session[:deliveries_return_to] = request.fullpath
    @deliveries = Delivery.joins(order: :client).merge(Delivery.with_service_cases).includes(:order, :delivery_address, :delivery_items).order("deliveries.delivery_date ASC, clients.name ASC").page(params[:page])
    render :index
  end

  def addresses_for_client
    client = Client.find(params[:client_id])
    render json: client.delivery_addresses.select(:id, :address)
  end

  def orders_for_client
    client = Client.find(params[:client_id])
    render json: client.orders.select(:id, :number)
  end

  def note
    render partial: "delivery_items/form_note", locals: { delivery: @delivery }
  end

  private

  def set_delivery
    @delivery = Delivery.find(params[:id])
  end

  def set_addresses
    @addresses = @delivery&.order&.client&.delivery_addresses&.to_a || []
  end

  def safe_date(str)
    str.present? ? Date.parse(str) : nil
  end

  # 🔹 Helpers de error centralizados
  def handle_create_error(e)
    Rails.logger.error "Error crear entrega: #{e.message}"
    @delivery ||= Delivery.new
    @client = find_or_initialize_client_from_params
    @order = find_or_initialize_order_from_params(@client)
    @addresses = @client.delivery_addresses.to_a
    @clients = Client.all.order(:name)
    flash.now[:alert] = "Error al crear la entrega: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def handle_update_error(e)
    @order  = @delivery.order
    @client = @order.client
    @addresses = @client.delivery_addresses.order(:description)
    flash.now[:alert] = "Error al actualizar la entrega: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  def handle_internal_error(e)
    @delivery ||= Delivery.new(delivery_type: :internal_delivery)
    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
    flash.now[:alert] = "Error al crear el mandado interno: #{e.message}"
    render :new_internal_delivery, status: :unprocessable_entity
  end

  def handle_service_case_error(e)
    @delivery ||= Delivery.new(delivery_type: params.dig(:delivery, :delivery_type) || :pickup)
    @clients = Client.all.order(:name)
    @addresses = @delivery.order&.client&.delivery_addresses || []
    @order = @delivery.order
    flash.now[:alert] = "Error al crear el caso de servicio: #{e.message}"
    render :new_service_case, status: :unprocessable_entity
  end

  def handle_service_case_existing_error(e, parent_delivery)
    @service_case ||= Delivery.new(
      order: parent_delivery.order,
      delivery_address: parent_delivery.delivery_address,
      delivery_type: params.dig(:delivery, :delivery_type) || :pickup,
      delivery_date: params.dig(:delivery, :delivery_date)
    )
    flash.now[:alert] = "Error al generar caso de servicio: #{e.message}"
    render :new_service_case_for_existing, status: :unprocessable_entity
  end
end
