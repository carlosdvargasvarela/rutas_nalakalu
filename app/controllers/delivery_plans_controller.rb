# app/controllers/delivery_plans_controller.rb
class DeliveryPlansController < ApplicationController
  def new
    # Rango de fechas
    if params.dig(:q, :delivery_date_gteq).present? && params.dig(:q, :delivery_date_lteq).present?
      from = Date.parse(params[:q][:delivery_date_gteq])
      to = Date.parse(params[:q][:delivery_date_lteq])
    else
      from = to = Date.today
    end

    # Solo entregas en el rango y con estado ready_to_deliver, no asignadas a un plan
    base_scope = Delivery
      .where(delivery_date: from..to)
      .where(status: :ready_to_deliver)
      .where.not(id: DeliveryPlanAssignment.select(:delivery_id))

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, order: :client).order(:delivery_date)
    @delivery_plan = DeliveryPlan.new
    @from = from
    @to = to
  end

  def create
    @delivery_plan = DeliveryPlan.new(delivery_plan_params)
    delivery_ids = params[:delivery_ids]

    if delivery_ids.blank?
      redirect_to new_delivery_plan_path, alert: "Debes seleccionar al menos una entrega." and return
    end

    # Cargar las entregas seleccionadas
    deliveries = Delivery.where(id: delivery_ids)
    unique_dates = deliveries.pluck(:delivery_date).uniq

    if unique_dates.size > 1
      redirect_to new_delivery_plan_path, alert: "Todas las entregas seleccionadas deben tener la misma fecha." and return
    end

    if @delivery_plan.save
      delivery_ids.each do |delivery_id|
        DeliveryPlanAssignment.create!(delivery_plan: @delivery_plan, delivery_id: delivery_id)
      end
      redirect_to @delivery_plan, notice: "Plan de ruta creado exitosamente."
    else
      redirect_to new_delivery_plan_path, alert: "Error al crear el plan de ruta."
    end
  end

  def show
    @delivery_plan = DeliveryPlan.find(params[:id])
    @deliveries = @delivery_plan.deliveries.includes(:order, :delivery_address, order: :client)
  end

  def edit
    @delivery_plan = DeliveryPlan.find(params[:id])
    @assignments = @delivery_plan.delivery_plan_assignments.includes(delivery: [:order, :delivery_address, order: :client]).order(:stop_order)
  end

  def update
    @delivery_plan = DeliveryPlan.find(params[:id])

    # Actualiza los datos del plan (incluyendo driver_id)
    @delivery_plan.update(delivery_plan_params)

    # Actualiza el orden de las paradas
    if params[:stop_orders]
      params[:stop_orders].each do |assignment_id, stop_order|
        assignment = @delivery_plan.delivery_plan_assignments.find(assignment_id)
        assignment.update(stop_order: stop_order)
      end
    end

    redirect_to @delivery_plan, notice: "Plan de ruta actualizado correctamente."
  end

  def send_to_logistics
    @delivery_plan = DeliveryPlan.find(params[:id])
    if @delivery_plan.driver.present?
      @delivery_plan.update!(status: :sent_to_logistics)
      redirect_to @delivery_plan, notice: "Plan enviado a logística."
    else
      redirect_to edit_delivery_plan_path(@delivery_plan), alert: "Debes asignar un conductor antes de enviar a logística."
    end
  end

  private

  def delivery_plan_params
    params.require(:delivery_plan).permit(:week, :year, :status, :driver_id)
  end
end