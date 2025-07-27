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
    # @delivery ya está seteada por before_action
  end

  private

  def set_delivery
    @delivery = Delivery.find(params[:id])
  end
end