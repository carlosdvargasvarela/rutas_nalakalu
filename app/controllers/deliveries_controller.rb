# app/controllers/deliveries_controller.rb
class DeliveriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_delivery, only: [:show]

  # GET /deliveries
  # Muestra todas las entregas o filtra por semana
  def index
    @deliveries = Delivery.includes(:order, :delivery_address, :delivery_items)

    if params[:week].present? && params[:year].present?
      # Calcula la fecha de inicio de la semana
      start_date = Date.commercial(params[:year].to_i, params[:week].to_i, 1)
      @deliveries = @deliveries.for_week(start_date)
    end

    # Ordenar por fecha de entrega y luego por cliente
    @deliveries = @deliveries.order(:delivery_date, 'clients.name').page(params[:page])
  end

  # GET /deliveries/by_week
  # Muestra un formulario simple para seleccionar semana y año
  def by_week
    @week = params[:week] || Date.today.cweek
    @year = params[:year] || Date.today.cwyear
    @deliveries = Delivery.for_week(Date.commercial(@year.to_i, @week.to_i, 1))
                          .includes(:order, :delivery_address, :delivery_items)
                          .order(:delivery_date, 'clients.name')
                          .page(params[:page])
    render :index # Reutiliza la vista index
  end

  # GET /deliveries/service_cases
  # Muestra solo las entregas que contienen casos de servicio
  def service_cases
    @deliveries = Delivery.with_service_cases
                          .includes(:order, :delivery_address, :delivery_items)
                          .order(:delivery_date, 'clients.name')
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