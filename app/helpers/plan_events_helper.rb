# app/helpers/plan_events_helper.rb
module PlanEventsHelper
  def plan_event_description(event)
    data = event.payload_data

    case event.action
    when "created"
      "Plan creado"
    when "sent_to_logistics"
      "Enviado a logística"
    when "routes_created"
      "Ruta creada"
    when "started"
      "Plan iniciado"
    when "finished"
      "Plan finalizado"
    when "aborted"
      "Plan abortado"
    when "stop_added"
      "Parada agregada: #{stop_label(data)}"
    when "stop_removed"
      "Parada quitada: #{stop_label(data)}"
    else
      event.label
    end
  end

  private

  def stop_label(data)
    data["delivery_label"].presence || "Entrega ##{data["delivery_id"]}"
  end
end
