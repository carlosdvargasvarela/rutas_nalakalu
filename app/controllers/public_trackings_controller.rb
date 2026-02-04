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

    # Coordenadas para el mapa (asegurando Floats para Google Maps)
    @truck_lat = @plan.current_lat&.to_f
    @truck_lng = @plan.current_lng&.to_f
    @dest_lat = @address.latitude&.to_f
    @dest_lng = @address.longitude&.to_f
  end
end
