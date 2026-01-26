# app/controllers/delivery_plans_controller.rb
class DeliveryPlansController < ApplicationController
  def index
    # 1. Configurar Ransack con un orden por defecto si no hay uno
    @q = DeliveryPlan.ransack(params[:q])
    @q.sorts = ["year desc", "week desc", "created_at desc"] if @q.sorts.empty?

    delivered_status = Delivery.statuses[:delivered]

    # 2. Consulta base con agregados
    base_result = @q.result
      .left_joins(:deliveries)
      .select(<<~SQL)
        delivery_plans.*,
        MIN(deliveries.delivery_date) AS first_delivery_date,
        MAX(deliveries.delivery_date) AS last_delivery_date,
        COUNT(deliveries.id)          AS deliveries_count,
        COUNT(
          CASE
            WHEN deliveries.status = #{delivered_status} THEN 1
          END
        ) AS delivered_count
      SQL
      .group("delivery_plans.id")
      .order(Arel.sql("delivery_plans.year DESC, delivery_plans.week DESC, delivery_plans.created_at DESC"))

    respond_to do |format|
      format.html do
        # 🔹 NUEVO: Calcular estadísticas globales ANTES de paginar
        all_plans = base_result.to_a

        @stats = {
          total_plans: all_plans.size,
          total_deliveries: all_plans.sum { |p| p.deliveries_count.to_i },
          by_status: all_plans.group_by(&:status).transform_values(&:size)
        }

        # Paginación para HTML
        @delivery_plans = Kaminari.paginate_array(all_plans)
          .page(params[:page])
          .per(15)

        # Para el filtro de camión en la vista
        @available_trucks = DeliveryPlan.distinct.pluck(:truck).compact.uniq
      end

      format.xlsx do
        @delivery_plans = @q.result
          .left_joins(:deliveries)
          .select(<<~SQL)
            delivery_plans.*,
            MIN(deliveries.delivery_date) AS first_delivery_date,
            MAX(deliveries.delivery_date) AS last_delivery_date
          SQL
          .group("delivery_plans.id")
          .order("delivery_plans.year DESC, delivery_plans.week DESC")
          .includes(
            :driver,
            delivery_plan_assignments: {
              delivery: [
                {order: [:client, :seller]},
                :delivery_address,
                {delivery_items: :order_item}
              ]
            }
          )
          .distinct
          .to_a

        response.headers["Content-Disposition"] =
          'attachment; filename="planes_entrega.xlsx"'
      end
    end
  end

  def new
    authorize DeliveryPlan
    if params.dig(:q, :delivery_date_gteq).present? && params.dig(:q, :delivery_date_lteq).present?
      from = Date.parse(params[:q][:delivery_date_gteq])
      to = Date.parse(params[:q][:delivery_date_lteq])
    else
      from = to = Date.today
    end

    base_scope = Delivery
      .where(delivery_date: from..to)
      .available_for_plan

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result
      .joins(order: :client)
      .includes(:delivery_address, order: :client)
      .order(:delivery_date, "clients.name": :asc)

    @delivery_plan = DeliveryPlan.new
    @from = from
    @to = to
  end

  def add_delivery_to_plan
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan
    delivery = Delivery.find(params[:delivery_id])

    if delivery.delivery_date == @delivery_plan.deliveries.first.delivery_date &&
        !DeliveryPlanAssignment.exists?(delivery_id: delivery.id)

      grouper = DeliveryPlanStopGrouper.new(@delivery_plan)
      existing_stop = grouper.find_stop_for_location(delivery)

      if existing_stop
        # Crear sin callbacks y luego asignar stop_order manualmente
        assignment = DeliveryPlanAssignment.new(
          delivery_plan: @delivery_plan,
          delivery_id: delivery.id
        )
        assignment.save(validate: false)
        assignment.update_column(:stop_order, existing_stop)

        redirect_to edit_delivery_plan_path(@delivery_plan),
          notice: "Entrega agregada al plan en la parada ##{existing_stop} (misma ubicación)."
      else
        last_order = @delivery_plan.delivery_plan_assignments.maximum(:stop_order) || 0

        assignment = DeliveryPlanAssignment.new(
          delivery_plan: @delivery_plan,
          delivery_id: delivery.id
        )
        assignment.save(validate: false)
        assignment.update_column(:stop_order, last_order + 1)

        redirect_to edit_delivery_plan_path(@delivery_plan),
          notice: "Entrega agregada al plan como nueva parada."
      end
    else
      redirect_to edit_delivery_plan_path(@delivery_plan),
        alert: "No se pudo agregar la entrega."
    end
  end

  def update_order
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    stop_orders = params[:stop_orders] || {}

    ActiveRecord::Base.transaction do
      # Evitar N+1 al buscar assignments uno por uno
      assignments = @delivery_plan.delivery_plan_assignments
        .where(id: stop_orders.keys)
        .index_by { |a| a.id.to_s }

      stop_orders.each do |assignment_id, stop_order|
        if (assignment = assignments[assignment_id.to_s])
          assignment.update!(stop_order: stop_order.to_i)
        end
      end

      # Reagrupar después de reordenar manualmente
      DeliveryPlanStopGrouper.new(@delivery_plan).call
    end

    render json: {status: "success"}
  rescue => e
    Rails.logger.error("[DeliveryPlansController#update_order] #{e.class}: #{e.message}")
    render json: {status: "error", message: e.message}, status: :unprocessable_entity
  end

  def create
    @delivery_plan = DeliveryPlan.new(delivery_plan_params)
    authorize @delivery_plan
    delivery_ids = Array(params[:delivery_ids]).reject(&:blank?)

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

    first_date = unique_dates.first
    @delivery_plan.week = first_date.cweek
    @delivery_plan.year = first_date.cwyear

    if @delivery_plan.save
      # Evitar N+1 al volver a buscar cada Delivery
      deliveries_by_id = deliveries.index_by { |d| d.id.to_s }

      delivery_ids.each_with_index do |delivery_id, index|
        DeliveryPlanAssignment.create!(
          delivery_plan: @delivery_plan,
          delivery_id: delivery_id,
          stop_order: index + 1
        )

        if (delivery = deliveries_by_id[delivery_id.to_s])
          delivery.update_status_based_on_items
        end
      end

      # Agrupar paradas por ubicación
      DeliveryPlanStopGrouper.new(@delivery_plan).call

      redirect_to edit_delivery_plan_path(@delivery_plan),
        notice: "Plan de ruta creado exitosamente. Las paradas fueron agrupadas por ubicación."
    else
      flash.now[:alert] = "Error al crear el plan de ruta."
      render_new_with_selection(delivery_ids)
    end
  end

  def show
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    @deliveries = @delivery_plan.deliveries
      .includes(:delivery_address, order: :client)

    @assignments = @delivery_plan.delivery_plan_assignments
      .includes(
        delivery: [
          :delivery_items,
          {order: [:client, :seller]},
          {delivery_address: :client}
        ]
      )
      .order(:stop_order)

    delivery_dates = @deliveries.pluck(:delivery_date)
    @from_date = delivery_dates.min
    @to_date = delivery_dates.max

    respond_to do |format|
      format.html
      format.xlsx do
        response.headers["Content-Disposition"] =
          "attachment; filename=Hoja_Ruta_#{@from_date&.strftime("%d_%m_%Y")}_#{@delivery_plan.truck.presence || "Sin_Camion"}.xlsx"
      end
      format.pdf do
        pdf_title = "Hoja_Ruta_#{@from_date&.strftime("%d_%m_%Y")}_#{@delivery_plan.truck.presence || "Sin_Camion"}"
        pdf = Prawn::Document.new(page_size: "A2", page_layout: :landscape)
        pdf.text pdf_title, size: 16, style: :bold, align: :center
        pdf.move_down 20
        headers = [
          "# Parada", "Pedido", "Producto", "Cantidad", "Cliente", "Vendedor",
          "Dirección", "Hora", "Fecha", "Contacto", "Teléfono", "Notas", "Estado"
        ]
        rows = @assignments.flat_map do |assignment|
          delivery = assignment.delivery
          address = delivery.delivery_address
          delivery.active_items_for_plan_for(current_user).map do |item|
            address_text = [address.address, address.description].compact.join(" - ")
            map_link =
              if address.latitude.present? && address.longitude.present?
                " (Waze: https://waze.com/ul?ll=#{address.latitude},#{address.longitude}&navigate=yes)"
              elsif address.address.present?
                " (Waze: https://waze.com/ul?q=#{ERB::Util.url_encode(address.address)}&navigate=yes)"
              else
                ""
              end
            full_address = "#{address_text}#{map_link}"
            notes = []
            notes << "PRODUCCIÓN: #{item.order_item.notes}" if item.order_item.notes.present?
            notes << "LOGÍSTICA: #{item.notes}" if item.notes.present?
            notes << "VENDEDOR: #{delivery.delivery_notes}" if delivery.delivery_notes.present?
            [
              assignment.stop_order,
              delivery.order.number,
              item.order_item.product,
              item.quantity_delivered,
              delivery.order.client.name,
              delivery.order.seller.seller_code,
              full_address,
              delivery.delivery_time_preference.presence || "Sin preferencia",
              I18n.l(delivery.delivery_date, format: :long),
              delivery.contact_name,
              delivery.contact_phone.presence || "-",
              notes.join("\n"),
              item.display_status
            ]
          end
        end
        pdf.table([headers] + rows, header: true,
          row_colors: %w[F0F0F0 FFFFFF],
          position: :center,
          cell_style: {inline_format: true})
        send_data pdf.render,
          filename: "#{pdf_title}.pdf",
          type: "application/pdf",
          disposition: "attachment"
      end

      format.json do
        render json: {
          id: @delivery_plan.id,
          truck: @delivery_plan.truck,
          status: @delivery_plan.status,
          current_lat: @delivery_plan.current_lat,
          current_lng: @delivery_plan.current_lng,
          last_seen_at: @delivery_plan.last_seen_at,
          assignments: @assignments.map do |a|
            addr = a.delivery.delivery_address
            {
              id: a.id,
              stop_order: a.stop_order,
              status: a.status,
              delivery: {
                id: a.delivery.id,
                contact_name: a.delivery.contact_name,
                contact_phone: a.delivery.contact_phone,
                delivery_notes: a.delivery.delivery_notes,
                latitude: addr&.latitude,
                longitude: addr&.longitude,
                address: addr&.address,
                description: addr&.description,
                plus_code: addr&.plus_code
              }
            }
          end
        }
      end
    end
  end

  def edit
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    @assignments = @delivery_plan.delivery_plan_assignments
      .includes(delivery: [:delivery_address, {order: :client}])
      .order(:stop_order)

    delivery_date = @assignments.first&.delivery&.delivery_date

    @available_deliveries = if delivery_date
      Delivery
        .where(delivery_date: delivery_date)
        .available_for_plan
        .includes(:delivery_address, order: :client)
    else
      []
    end
  end

  def destroy
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    if @delivery_plan.destroy
      redirect_to delivery_plans_path, notice: "Plan de ruta eliminado correctamente."
    else
      alert_message = @delivery_plan.errors.full_messages.presence || ["No se pudo eliminar el plan de ruta."]
      redirect_back fallback_location: delivery_plans_path, alert: alert_message.join(". ")
    end
  end

  def update
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    if @delivery_plan.update(delivery_plan_params)
      redirect_to edit_delivery_plan_path(@delivery_plan),
        notice: "Plan de ruta actualizado correctamente."
    else
      flash.now[:alert] = @delivery_plan.errors.full_messages.to_sentence.presence ||
        "No se pudo actualizar el plan de ruta."

      @assignments = @delivery_plan.delivery_plan_assignments
        .includes(delivery: [:delivery_address, {order: :client}])
        .order(:stop_order)

      delivery_date = @assignments.first&.delivery&.delivery_date
      @available_deliveries = if delivery_date
        Delivery.where(delivery_date: delivery_date)
          .available_for_plan
          .includes(:delivery_address, order: :client)
      else
        []
      end

      render :edit, status: :unprocessable_entity
    end
  end

  def send_to_logistics
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan
    if @delivery_plan.driver.present?
      @delivery_plan.update!(status: :routes_created)
      redirect_to @delivery_plan, notice: "Plan enviado a logística."
    else
      redirect_to edit_delivery_plan_path(@delivery_plan), alert: "Debes asignar un conductor y confirmar todas las entregas antes de enviar a logística."
    end
  end

  private

  def delivery_plan_params
    params.require(:delivery_plan).permit(:week, :year, :status, :driver_id, :truck)
  end

  def render_new_with_selection(selected_ids)
    if params.dig(:q, :delivery_date_gteq).present? && params.dig(:q, :delivery_date_lteq).present?
      from = Date.parse(params[:q][:delivery_date_gteq])
      to = Date.parse(params[:q][:delivery_date_lteq])
    else
      from = to = Date.today
    end

    base_scope = Delivery
      .where(delivery_date: from..to)
      .where(status: [:scheduled, :ready_to_deliver])
      .where.not(id: DeliveryPlanAssignment.select(:delivery_id))

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result
      .includes(:delivery_address, order: :client)
      .order(:delivery_date)

    @from = from
    @to = to
    @selected_delivery_ids = selected_ids.map(&:to_i)
    render :new, status: :unprocessable_entity
  end
end
