# Turbo Streams que refrescan la bitácora de carga tras cambiar el estado de
# un producto o de una parada: encabezado, resumen, parada en la lista y panel
# de detalle (siempre de la parada que el operario tiene abierta).
module LoadingStreams
  extend ActiveSupport::Concern

  private

  def loading_streams(delivery)
    plan = delivery.delivery_plan
    return [] unless plan

    assignment = delivery.delivery_plan_assignment
    stats = plan.load_stats

    [
      turbo_stream.replace("plan_header", partial: "production/delivery_plans/plan_header", locals: {delivery_plan: plan, load_stats: stats}),
      turbo_stream.replace("stop_#{delivery.id}", partial: "production/delivery_plans/stop_row", locals: {delivery: delivery, assignment: assignment, plan: plan, selected: true}),
      turbo_stream.replace("stop_detail", partial: "production/delivery_plans/stop_detail", locals: {delivery: delivery, assignment: assignment, plan: plan})
    ]
  end
end
