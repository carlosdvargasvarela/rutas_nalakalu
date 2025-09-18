# app/controllers/delivery_plans_controller.rb
class DeliveryPlansController < ApplicationController
  def index
    authorize DeliveryPlan
    @q = DeliveryPlan.ransack(params[:q])
    @delivery_plans = @q.result.includes(:driver, :deliveries).sort_by(&:first_delivery_date)
  end

  def new
    # Rango de fechas
    authorize DeliveryPlan
    if params.dig(:q, :delivery_date_gteq).present? && params.dig(:q, :delivery_date_lteq).present?
      from = Date.parse(params[:q][:delivery_date_gteq])
      to = Date.parse(params[:q][:delivery_date_lteq])
    else
      from = to = Date.today
    end

    # Usar el scope para entregas disponibles para planes
    base_scope = Delivery
      .where(delivery_date: from..to)
      .available_for_plan

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, order: :client).order(:delivery_date)
    @delivery_plan = DeliveryPlan.new
    @from = from
    @to = to
  end

  def create
    @delivery_plan = DeliveryPlan.new(delivery_plan_params)
    authorize @delivery_plan
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

    # Calcular week y year basado en las entregas
    first_date = unique_dates.first
    @delivery_plan.week = first_date.cweek
    @delivery_plan.year = first_date.cwyear

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
    authorize @delivery_plan
    @deliveries = @delivery_plan.deliveries.includes(:order, :delivery_address, order: :client)
    @assignments = @delivery_plan.delivery_plan_assignments.includes(
      delivery: [
        :delivery_items,
        order: [ :client, :seller ],
        delivery_address: :client
      ]
    ).order(:stop_order)

    # Calcular rango de fechas desde las entregas
    delivery_dates = @deliveries.pluck(:delivery_date)
    @from_date = delivery_dates.min
    @to_date = delivery_dates.max

    respond_to do |format|
      format.html
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=Hoja_Ruta_#{@from_date&.strftime('%d_%m_%Y')}_#{@delivery_plan.truck.presence || 'Sin_Camion'}.xlsx"
      }
      format.pdf do
        pdf_title = "Hoja_Ruta_#{@from_date&.strftime('%d_%m_%Y')}_#{@delivery_plan.truck.presence || 'Sin_Camion'}"

        pdf = Prawn::Document.new(page_size: "A2", page_layout: :landscape) # Hoja A3 landscape

        pdf.text pdf_title, size: 16, style: :bold, align: :center
        pdf.move_down 20

        headers = [
          "# Parada", "Pedido", "Cliente", "Vendedor",
          "Dirección", # <-- Aquí vamos a incluir el link
          "Hora", "Fecha", "Estado", "Contacto", "Teléfono",
          "Producto", "Cantidad", "Notas"
        ]

        rows = @assignments.flat_map do |assignment|
          delivery = assignment.delivery
          address = delivery.delivery_address

          delivery.delivery_items.map do |item|
            address_text = [address.address, address.description].compact.join(" - ")
            map_link_text = ""

            if address.latitude.present? && address.longitude.present?
              map_link_text = " (Maps: https://www.google.com/maps?q=#{address.latitude},#{address.longitude})"
            elsif address.address.present?
              map_link_text = " (Maps: https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(address.address)})"
            end

            # Combinamos la dirección y el link de Maps
            full_address_cell = "#{address_text}#{map_link_text}"

            # 🔹 Combinar notas en listado
            all_notes = []
            all_notes << "PRODUCCIÓN: #{item.order_item.notes}" if item.order_item.notes.present?
            all_notes << "LOGÍSTICA: #{item.notes}" if item.notes.present?
            notes_text = all_notes.join("\n")

            [
              assignment.stop_order,
              delivery.order.number,
              delivery.order.client.name,
              delivery.order.seller.seller_code,
              full_address_cell,
              delivery.delivery_time_preference.presence || "Sin preferencia",
              I18n.l(delivery.delivery_date, format: :long),
              delivery.display_status,
              delivery.contact_name,
              delivery.contact_phone.presence || "-",
              item.order_item.product,
              item.quantity_delivered,
              notes_text
            ]
          end
        end

        pdf.table([headers] + rows,
                  header: true,
                  row_colors: ["F0F0F0", "FFFFFF"],
                  position: :center,
                  cell_style: { inline_format: true } # <-- ¡Importante para que los links sean clickeables!
                )

        send_data pdf.render,
                  filename: "#{pdf_title}.pdf",
                  type: "application/pdf",
                  disposition: "attachment"
      end
    end
  end

  def edit
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan
    @assignments = @delivery_plan.delivery_plan_assignments.includes(delivery: [ :order, :delivery_address, order: :client ]).order(:stop_order)

    # Fecha de las entregas ya asignadas (todas deben ser iguales)
    delivery_date = @assignments.first&.delivery&.delivery_date

    # Entregas disponibles para agregar usando el scope
    @available_deliveries = if delivery_date
      Delivery
        .where(delivery_date: delivery_date)
        .available_for_plan
    else
      []
    end
  end

  def update
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

    if @delivery_plan.update(delivery_plan_params)
      # Actualiza el orden de las paradas
      if params[:stop_orders]
        params[:stop_orders].each do |assignment_id, stop_order|
          assignment = @delivery_plan.delivery_plan_assignments.find(assignment_id)
          assignment.update(stop_order: stop_order)
        end
      end

      redirect_to @delivery_plan, notice: "Plan de ruta actualizado correctamente."
    else
      # Si hay errores, volver a cargar los datos necesarios para la vista
      @assignments = @delivery_plan.delivery_plan_assignments.includes(
        delivery: [ :order, :delivery_address, order: :client ]
      ).order(:stop_order)

      delivery_date = @assignments.first&.delivery&.delivery_date
      @available_deliveries = if delivery_date
        Delivery
          .where(delivery_date: delivery_date)
          .where(status: :ready_to_deliver)
          .where.not(id: DeliveryPlanAssignment.select(:delivery_id))
      else
        []
      end

      render :edit, status: :unprocessable_entity
    end
  end

  def send_to_logistics
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan
    if @delivery_plan.driver.present? && @delivery_plan.all_deliveries_confirmed?
      @delivery_plan.update!(status: :sent_to_logistics)
      redirect_to @delivery_plan, notice: "Plan enviado a logística."
    else
      redirect_to edit_delivery_plan_path(@delivery_plan), alert: "Debes asignar un conductor y confirmar todas las entregas antes de enviar a logística."
    end
  end

  def update_order
    @delivery_plan = DeliveryPlan.find(params[:id])
    authorize @delivery_plan

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
    authorize @delivery_plan
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
    params.require(:delivery_plan).permit(:week, :year, :status, :driver_id, :truck)
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
      .where(status: [ :scheduled, :ready_to_deliver ])
      .where.not(id: DeliveryPlanAssignment.select(:delivery_id))

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result.includes(:order, :delivery_address, order: :client).order(:delivery_date)
    @from = from
    @to = to
    @selected_delivery_ids = selected_ids.map(&:to_i)
    render :new, status: :unprocessable_entity
  end
end
