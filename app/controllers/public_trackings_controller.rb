# app/controllers/public_trackings_controller.rb
class PublicTrackingsController < ApplicationController
  # 🔓 Permitir acceso sin login
  skip_before_action :authenticate_user!

  # Layout específico para clientes (sin barras de navegación internas)
  layout "public"

  def show
    # 1. Buscar la entrega por su token único
    @delivery = Delivery.find_by!(tracking_token: params[:token])
    @assignment = @delivery.delivery_plan_assignment
    @plan = @assignment&.delivery_plan

    # 2. Autorizar explícitamente usando la PublicTrackingPolicy
    # Pasamos @delivery como el 'record' de la política
    authorize @delivery, policy_class: PublicTrackingPolicy

    if @plan.nil?
      render "no_plan", status: :not_found and return
    end

    @address = @delivery.delivery_address
    # El stage decide qué parcial se renderiza (ver show.html.erb); solo el
    # parcial de :live lee la posición del camión desde @plan. Antes de que
    # el conductor arranque ESTA parada, el cliente no debe poder ver por
    # dónde anda el camión (revelaría otras paradas de la ruta) ni asumir
    # que "ya viene" cuando aún no le toca.
    @stage = client_stage
  end

  private

  def client_stage
    return :issue if @delivery.rescheduled?
    return :issue if @assignment.cancelled?
    return :delivered if @assignment.completed?
    return :live if @assignment.in_route?
    :waiting
  end
end
