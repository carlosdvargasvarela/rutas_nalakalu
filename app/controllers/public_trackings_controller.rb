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
    @stop_assignments = stop_assignments
    @stop_orders = @stop_assignments.map { |a| a.delivery.order }.uniq.sort_by(&:number)
    @stage = client_stage

    # El mapa se actualiza por ActionCable en cuanto el celular del conductor
    # manda su posición, pero si el WebSocket se cae (red del cliente, tab en
    # background) no hay reintento automático que reponga los broadcasts
    # perdidos: el camión se queda pegado en el último punto. Este JSON es el
    # respaldo que el JS del mapa consulta cada ~15s pase lo que pase con el
    # socket.
    respond_to do |format|
      format.html
      format.json { render json: live_position_json }
    end
  end

  private

  # Asignaciones del MISMO cliente en esta misma parada (el grouper les da el
  # mismo stop_order): el cliente ve un solo seguimiento aunque haya varios
  # pedidos. Se filtra por cliente para no mostrar pedidos de otras personas
  # que comparten edificio.
  def stop_assignments
    @plan.delivery_plan_assignments.where(stop_order: @assignment.stop_order)
      .includes(delivery: :order)
      .select { |a| a.delivery.order.client_id == @delivery.order.client_id }
  end

  def client_stage
    return :issue if @delivery.rescheduled?
    return :issue if @assignment.cancelled?
    return :delivered if @assignment.completed?
    # Asociación blanda: si el conductor ya arrancó cualquier pedido de esta
    # parada, el camión ya está yendo al lugar de todos.
    return :live if @stop_assignments.any?(&:in_route?)
    :waiting
  end

  def live_position_json
    return {stage: @stage} unless @stage == :live

    {
      stage: @stage,
      current_lat: @plan.current_lat&.to_f,
      current_lng: @plan.current_lng&.to_f,
      last_seen_at: @plan.last_seen_at&.iso8601
    }
  end
end
