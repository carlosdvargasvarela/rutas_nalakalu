class TrackingsController < ApplicationController
  STATUS_FILTERS = %w[active completed all].freeze

  def index
    authorize :tracking, :index?

    @show_all = params[:show_all] == "1"
    @date = @show_all ? nil : (parse_date(params[:date]) || Date.current)
    @status_filter = STATUS_FILTERS.include?(params[:status]) ? params[:status] : "active"

    scope = case @status_filter
    when "completed" then DeliveryPlan.status_completed
    when "all" then DeliveryPlan.trackable
    else DeliveryPlan.active
    end
    scope = scope.with_deliveries_on(@date) if @date

    @plans = scope.includes(:driver, :last_recorded_by, delivery_plan_assignments: :delivery)
      .map { |plan| serialize_plan(plan) }
  end

  def route
    authorize :tracking, :index?
    # trackable (no solo active): un plan completado conserva su historial de
    # GPS y debe poder consultarse desde /tracking igual que uno en curso.
    plan = DeliveryPlan.trackable.find(params[:delivery_plan_id])

    points = plan.delivery_plan_locations.ordered.map do |loc|
      {lat: loc.latitude.to_f, lng: loc.longitude.to_f, captured_at: loc.captured_at}
    end

    render json: points
  end

  private

  def serialize_plan(plan)
    visible_assignments = plan.delivery_plan_assignments.reject { |a| a.delivery.hidden_from_route_map? }
    # Distingue en la lista dos planes con el mismo conductor/camión (p. ej.
    # una ruta de mañana y otra de tarde el mismo día, o una ruta vieja que
    # quedó activa): sin esto se ven como una sola fila/pin duplicado.
    dates = visible_assignments.filter_map { |a| a.delivery.delivery_date }.uniq.sort

    {
      id: plan.id,
      status: plan.status,
      display_status: plan.display_status,
      driver_name: plan.driver&.name || "Sin asignar",
      truck: plan.truck || "Sin asignar",
      current_lat: plan.current_lat&.to_f,
      current_lng: plan.current_lng&.to_f,
      last_seen_at: plan.last_seen_at,
      recorded_by_name: plan.last_recorded_by&.name,
      total_stops: visible_assignments.size,
      completed_stops: visible_assignments.count { |a| a.status == "completed" },
      date_label: dates.any? ? dates.map { |d| d.strftime("%d/%m") }.join(" - ") : nil
    }
  end
end
