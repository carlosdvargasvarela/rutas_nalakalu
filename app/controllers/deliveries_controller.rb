# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :set_delivery, only: [:show]

  # GET /deliveries
  # Muestra todas las entregas o filtra por semana
  def index
    @q = Delivery.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, :delivery_items).page(params[:page])
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
                          .order('deliveries.delivery_date ASC')
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
      .order('deliveries.delivery_date ASC, clients.name ASC')
      .page(params[:page])
    render :index # Reutiliza la vista index
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
    @addresses = @client&.delivery_addresses || []
  end

  def create
    ActiveRecord::Base.transaction do
      # 1. Cliente
      client =
        if params[:client_id].present?
          Client.find(params[:client_id])
        else
          # Busca por email o teléfono antes de crear
          existing = Client.find_by(email: params[:client][:email]) if params[:client][:email].present?
          existing ||= Client.find_by(phone: params[:client][:phone]) if params[:client][:phone].present?
          existing || Client.create!(params.require(:client).permit(:name, :phone, :email))
        end

      # 2. Dirección
      address =
        if params[:delivery_address_id].present?
          DeliveryAddress.find(params[:delivery_address_id])
        else
          # Busca dirección igual antes de crear
          existing = client.delivery_addresses.find_by(address: params[:delivery_address][:address]) if params[:delivery_address][:address].present?
          existing || client.delivery_addresses.create!(params.require(:delivery_address).permit(:address, :description))
        end

      # 3. Pedido
      order =
        if params[:order_id].present?
          Order.find(params[:order_id])
        else
          order = client.orders.create!(
            number: Order.generate_number,
            seller_id: params[:seller_id] || current_user.seller&.id,
            status: :pending
          )
          # Crear productos asociados
          if params[:order_items].blank?
            raise ActiveRecord::RecordInvalid.new(order), "Debes agregar al menos un producto al pedido."
          end
          params[:order_items].each do |item_params|
            order.order_items.create!(item_params.permit(:product, :quantity, :notes))
          end
          order
        end

      # 4. Entrega
      existing_delivery = order.deliveries.find_by(
        delivery_address: address,
        delivery_date: params[:delivery_date],
        delivery_type: params[:delivery_type]
      )
      delivery = existing_delivery || order.deliveries.create!(
        delivery_address: address,
        delivery_date: params[:delivery_date],
        contact_name: params[:contact_name],
        contact_phone: params[:contact_phone],
        delivery_type: params[:delivery_type],
        status: :ready_to_deliver
      )

      # 5. DeliveryItems (si es necesario)
      if params[:delivery_items]
        params[:delivery_items].each do |item_params|
          order_item = order.order_items.find(item_params[:order_item_id])
          delivery.delivery_items.create!(
            order_item: order_item,
            quantity_delivered: item_params[:quantity_delivered],
            status: item_params[:status]
          )
        end
      end

      redirect_to delivery, notice: "Entrega creada correctamente."
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Error al crear la entrega: #{e.message}"
    render :new
  end

  private

  def set_delivery
    @delivery = Delivery.find(params[:id])
  end
end