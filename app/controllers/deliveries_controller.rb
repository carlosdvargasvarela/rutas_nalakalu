# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :set_delivery, only: [ :show, :edit, :update ]

  # GET /deliveries
  # Muestra todas las entregas o filtra por semana
  def index
    @q = Delivery.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, :delivery_items).page(params[:page])
  end

  # GET /deliveries/:id
  # Muestra los detalles de una entrega específica
  def show
    @future_deliveries = Delivery
      .where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id)
      .where("delivery_date > ?", @delivery.delivery_date)
      .where.not(id: @delivery.id)
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

    # Para el formulario: lista de clientes y direcciones sugeridas
    @clients = Client.all.order(:name)
    @addresses = (@client&.delivery_addresses || []).to_a
  end

  def edit
    @delivery = Delivery.includes(delivery_items: :order_item).find(params[:id])
    @client = @delivery.order.client
    @addresses = @client.delivery_addresses.order(:description)
    @order = @delivery.order

    # Permitir agregar nuevos productos
    @delivery.delivery_items.build.build_order_item if @delivery.delivery_items.empty?
  end

  # PATCH/PUT /deliveries/:id
  def update
    ActiveRecord::Base.transaction do
      if @delivery.update(delivery_params)
        redirect_to @delivery, notice: "Entrega actualizada correctamente."
      else
        @client = @delivery.order.client
        @addresses = @client.delivery_addresses.order(:description)
        @order = @delivery.order
        render :edit, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @client = @delivery.order.client
    @addresses = @client.delivery_addresses.order(:description)
    @order = @delivery.order

    flash.now[:alert] = "Error al actualizar la entrega: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  def create
    ActiveRecord::Base.transaction do
      # 1. Cliente
      client = find_or_create_client

      # 2. Dirección
      address = find_or_create_address(client)

      # 3. Pedido
      order = find_or_create_order(client)

      # 4. Crear la entrega con productos anidados
      delivery_attrs = delivery_params.merge(
        order: order,
        delivery_address: address,
        status: :ready_to_deliver
      )

      @delivery = Delivery.new(delivery_attrs)

      if @delivery.save
        redirect_to @delivery, notice: "Entrega creada correctamente."
      else
        # Recargar datos para el formulario
        @client = client
        @order = order
        @clients = Client.all.order(:name)
        @addresses = client.delivery_addresses.to_a
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    handle_creation_error(e)
  end

  # GET /deliveries/by_week
  # Muestra un formulario simple para seleccionar semana y año
  def by_week
    @week = params[:week].to_i
    @year = params[:year].to_i

    # Si la semana es inválida, usa la semana actual
    @week = Date.today.cweek if @week < 1 || @week > 53
    @year = Date.today.cwyear if @year < 2000 # o el rango que prefieras

    start_date = Date.commercial(@year, @week, 1)
    @deliveries = Delivery.for_week(start_date)
                          .includes(order: :client, delivery_address: {}, delivery_items: {})
                          .order("deliveries.delivery_date ASC")
                          .page(params[:page])
    render :index
  end

  def mark_as_delivered
    @delivery = Delivery.find(params[:id])
    @delivery.mark_as_delivered!
    redirect_to @delivery, notice: "Entrega marcada como completada."
  end

  # GET /deliveries/service_cases
  # Muestra solo las entregas que contienen casos de servicio
  def service_cases
    @deliveries = Delivery
      .joins(order: :client)
      .merge(Delivery.with_service_cases)
      .includes(:order, :delivery_address, :delivery_items)
      .order("deliveries.delivery_date ASC, clients.name ASC")
      .page(params[:page])
    render :index # Reutiliza la vista index
  end

  def addresses_for_client
    client = Client.find(params[:client_id])
    addresses = client.delivery_addresses.select(:id, :address)
    render json: addresses
  end

  def orders_for_client
    client = Client.find(params[:client_id])
    orders = client.orders.select(:id, :number)
    render json: orders
  end

 private

 def find_or_create_client
    if params[:client_id].present?
      Client.find(params[:client_id])
    else
      existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
      existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
      existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
    end
  end

  def find_or_create_address(client)
    if params[:delivery] && params[:delivery][:delivery_address_id].present?
      DeliveryAddress.find(params[:delivery][:delivery_address_id])
    elsif params[:delivery_address] && params[:delivery_address][:address].present?
      existing = client.delivery_addresses.find_by(address: params[:delivery_address][:address])
      existing || client.delivery_addresses.create!(params.require(:delivery_address).permit(:address, :description))
    else
      raise ActiveRecord::RecordInvalid.new(DeliveryAddress.new), "Debes seleccionar o ingresar una dirección."
    end
  end

  def find_or_create_order(client)
    if params[:delivery] && params[:delivery][:order_id].present?
      Order.find(params[:delivery][:order_id])
    else
      client.orders.create!(
        number: params[:order][:number],
        seller_id: params[:seller_id] || current_user.seller&.id,
        status: :pending
      )
    end
  end

  def set_delivery
    @delivery = Delivery.find(params[:id])
    puts "Delivery found: #{@delivery.id} - #{@delivery.delivery_date}"
    puts @delivery
  end

  def delivery_params
    params.require(:delivery).permit(
      :delivery_date, :delivery_address_id, :contact_name, :contact_phone, :delivery_notes,
      delivery_items_attributes: [
        :id, :quantity_delivered, :service_case, :status, :_destroy,
        order_item_attributes: [ :id, :product, :quantity, :notes ]
      ]
    )
  end
end
