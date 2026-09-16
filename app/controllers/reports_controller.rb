class ReportsController < ApplicationController
  # Los .axlsx renderizan en el contexto de la vista, no del controller: sin
  # esto, truck_for/plan_note_for son invisibles ahí (NoMethodError) aunque
  # funcionen bien cuando se llaman desde el propio controller (ej. el PDF
  # de deliveries_by_client más abajo, que si corre en el controller).
  helper_method :truck_for, :plan_note_for

  def deliveries_by_client
    skip_authorization

    @from = parse_date(params[:from]) || Date.current.beginning_of_month
    @to   = parse_date(params[:to])   || Date.current.end_of_month

    @deliveries = Delivery
      .joins(order: :client)
      .includes(order: :client, delivery_plan_assignment: :delivery_plan)
      .where(delivery_date: @from..@to)
      .where.not(status: %w[cancelled archived])
      .order("clients.name ASC, deliveries.delivery_date ASC")

    seller_ids = Array(params[:seller_id]).reject(&:blank?)
    @deliveries = @deliveries.where(orders: {seller_id: seller_ids}) if seller_ids.present?

    statuses = Array(params[:status]).reject(&:blank?)
    @deliveries = @deliveries.where(status: statuses) if statuses.present?

    if params[:only_service_cases].present?
      @deliveries = Delivery.filter_by_predicate(@deliveries, :requires_service_case_action?)
    end

    if params[:only_repair_services].present?
      @deliveries = Delivery.filter_by_predicate(@deliveries, :requires_repair_service_action?)
    end

    respond_to do |format|
      format.html

      format.xlsx do
        response.headers["Content-Disposition"] =
          "attachment; filename=entregas_por_cliente_#{@from}_#{@to}.xlsx"
      end

      format.pdf do
        title = "Entregas por cliente #{I18n.l(@from, format: :long)} – #{I18n.l(@to, format: :long)}"

        pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape)
        pdf.font_size 11
        pdf.text title, size: 16, style: :bold, align: :center
        pdf.move_down 12

        headers = ["Cliente", "Fecha", "Pedido", "Camión"]
        rows = @deliveries.map do |d|
          [
            d.order.client.name,
            I18n.l(d.delivery_date, format: :long),
            d.order.number,
            truck_for(d)
          ]
        end

        if rows.any?
          pdf.table([headers] + rows, header: true, position: :center,
            cell_style: { size: 11, padding: [5, 8] }) do
            row(0).style(background_color: "1B3A6B", text_color: "FFFFFF", font_style: :bold)
            rows(1..-1).each_with_index { |r, i| r.style(background_color: i.even? ? "EEF4FB" : "FFFFFF") }
          end
        else
          pdf.text "Sin entregas para el período seleccionado.", align: :center, style: :italic
        end

        send_data pdf.render,
          filename: "entregas_por_cliente_#{@from}_#{@to}.pdf",
          type: "application/pdf",
          disposition: "attachment"
      end
    end
  end

  # Igual a Deliveries#index (mismos filtros de q/only_service_cases/
  # only_repair_services/show_archived) pero solo entregas que sí llegaron a
  # asignarse a un plan de ruta — sirve para auditar qué se agregó a los
  # planes en un período, incluyendo las que luego se reagendaron o
  # cancelaron (con nota visible en vez de desaparecer del reporte).
  def deliveries_in_plan
    authorize Delivery, :index?

    excluded_from_index = params[:show_archived] == "1" ? [] : [:archived]
    base_scope = Delivery.joins(:delivery_plan_assignment).where.not(status: excluded_from_index)

    if params[:only_service_cases].present?
      base_scope = Delivery.filter_by_predicate(base_scope, :requires_service_case_action?)
    end

    if params[:only_repair_services].present?
      base_scope = Delivery.filter_by_predicate(base_scope, :requires_repair_service_action?)
    end

    @q = base_scope.ransack(params[:q])
    @deliveries = @q.result.distinct
      .includes(
        order: [:client, :seller],
        delivery_address: :client,
        delivery_items: {order_item: :order},
        delivery_plan_assignment: {delivery_plan: :driver}
      )
      .order(delivery_date: :asc)

    respond_to do |format|
      format.xlsx do
        response.headers["Content-Disposition"] =
          "attachment; filename=entregas_en_plan_#{Date.current.strftime("%Y%m%d")}.xlsx"
      end
    end
  end

  private

  def truck_for(delivery)
    delivery.delivery_plan_assignment&.delivery_plan&.truck || "Sin asignar"
  end

  # Nota visible para el reporte de "entregas en plan": el estado por sí solo
  # no explica qué pasó, así que aquí se arma el detalle (a qué entrega/fecha
  # se reagendó, o que se canceló) en vez de dejar que el Excel solo diga
  # "Reprogramada"/"Cancelada" sin contexto.
  def plan_note_for(delivery)
    case delivery.status
    when "rescheduled"
      next_delivery = delivery.next_rescheduled_delivery
      if next_delivery
        "REAGENDADA → nueva entrega el #{I18n.l(next_delivery.delivery_date, format: :long)} (pedido #{next_delivery.order.number})"
      else
        "REAGENDADA"
      end
    when "cancelled"
      ["CANCELADA", delivery.delivery_notes.presence].compact.join(" — ")
    else
      delivery.delivery_notes.presence || ""
    end
  end
end
