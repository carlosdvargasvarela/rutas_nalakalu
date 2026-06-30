class ReportsController < ApplicationController
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

  private

  def parse_date(val)
    Date.parse(val) if val.present?
  rescue ArgumentError
    nil
  end

  def truck_for(delivery)
    delivery.delivery_plan_assignment&.delivery_plan&.truck || "Sin asignar"
  end
end
