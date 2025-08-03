# app/controllers/delivery_plans_controller.rb
class DeliveryPlansController < ApplicationController
  def index
    @q = DeliveryPlan.ransack(params[:q])
    @delivery_plans = @q.result.includes(:driver).order(year: :desc, week: :desc)
  end
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
    delivery_ids = params[:delivery_ids] || []

    # Cargar las entregas seleccionadas
    deliveries = Delivery.where(id: delivery_ids)
    unique_dates = deliveries.pluck(:delivery_date).uniq

    if delivery_ids.blank?
      flash.now[:alert] = "Debes seleccionar al menos una entrega."
      return render_new_with_selection(delivery_ids)
    end

    if unique_dates.size > 1
      flash.now[:alert] = "Todas las entregas seleccionadas deben tener la misma fecha."
      return render_new_with_selection(delivery_ids)
    end

    if @delivery_plan.save
      delivery_ids.each do |delivery_id|
        DeliveryPlanAssignment.create!(delivery_plan: @delivery_plan, delivery_id: delivery_id)
      end
      redirect_to edit_delivery_plan_path(@delivery_plan), notice: "Plan de ruta creado exitosamente. Ahora puedes ajustar el orden o asignar conductor."
    else
      flash.now[:alert] = "Error al crear el plan de ruta."
      render_new_with_selection(delivery_ids)
    end
  end

  def show
    @delivery_plan = DeliveryPlan.find(params[:id])
    @deliveries = @delivery_plan.deliveries.includes(:order, :delivery_address, order: :client)
  end

  def edit
    @delivery_plan = DeliveryPlan.find(params[:id])
    @assignments = @delivery_plan.delivery_plan_assignments.includes(delivery: [ :order, :delivery_address, order: :client ]).order(:stop_order)

    # Fecha de las entregas ya asignadas (todas deben ser iguales)
    delivery_date = @assignments.first&.delivery&.delivery_date

    # Entregas disponibles para agregar (mismo día, no asignadas a ningún plan)
    @available_deliveries = if delivery_date
      Delivery
        .where(delivery_date: delivery_date)
        .where(status: :ready_to_deliver)
        .where.not(id: DeliveryPlanAssignment.select(:delivery_id))
    else
      []
    end
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

  def update_order
    @delivery_plan = DeliveryPlan.find(params[:id])

    if params[:stop_orders]
      params[:stop_orders].each do |assignment_id, stop_order|
        assignment = @delivery_plan.delivery_plan_assignments.find(assignment_id)
        assignment.update(stop_order: stop_order)
      end
    end

    render json: { status: "success" }
  rescue => e
    render json: { status: "error", message: e.message }, status: 422
  end

  def add_delivery_to_plan
    @delivery_plan = DeliveryPlan.find(params[:id])
    delivery = Delivery.find(params[:delivery_id])

    # Validación: misma fecha y no asignada
    if delivery.delivery_date == @delivery_plan.deliveries.first.delivery_date &&
      !DeliveryPlanAssignment.exists?(delivery_id: delivery.id)
      DeliveryPlanAssignment.create!(delivery_plan: @delivery_plan, delivery_id: delivery.id)
      redirect_to edit_delivery_plan_path(@delivery_plan), notice: "Entrega agregada al plan."
    else
      redirect_to edit_delivery_plan_path(@delivery_plan), alert: "No se pudo agregar la entrega."
    end
  end

  private

  def delivery_plan_params
    params.require(:delivery_plan).permit(:week, :year, :status, :driver_id)
  end

  def render_new_with_selection(selected_ids)
    # Rango de fechas
    if params.dig(:q, :delivery_date_gteq).present? && params.dig(:q, :delivery_date_lteq).present?
      from = Date.parse(params[:q][:delivery_date_gteq])
      to = Date.parse(params[:q][:delivery_date_lteq])
    else
      from = to = Date.today
    end

    base_scope = Delivery
      .where(delivery_date: from..to)
      .where(status: :ready_to_deliver)
      .where.not(id: DeliveryPlanAssignment.select(:delivery_id))

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, order: :client).order(:delivery_date)
    @from = from
    @to = to
    @selected_delivery_ids = selected_ids.map(&:to_i)
    render :new, status: :unprocessable_entity
  end
end
