class TrackingsController < ApplicationController
  def index
    authorize :tracking, :index?

    @plans = DeliveryPlan.active
      .includes(:driver, :last_recorded_by, delivery_plan_assignments: :delivery)
      .map { |plan| serialize_plan(plan) }
  end

  def route
    authorize :tracking, :index?
    plan = DeliveryPlan.active.find(params[:delivery_plan_id])

    points = plan.delivery_plan_locations.ordered.map do |loc|
      {lat: loc.latitude.to_f, lng: loc.longitude.to_f, captured_at: loc.captured_at}
    end

    render json: points
  end

  private

  def serialize_plan(plan)
    visible_assignments = plan.delivery_plan_assignments.reject { |a| a.delivery.hidden_from_route_map? }

    {
      id: plan.id,
      driver_name: plan.driver&.name || "Sin asignar",
      truck: plan.truck || "Sin asignar",
      current_lat: plan.current_lat&.to_f,
      current_lng: plan.current_lng&.to_f,
      last_seen_at: plan.last_seen_at,
      recorded_by_name: plan.last_recorded_by&.name,
      total_stops: visible_assignments.size,
      completed_stops: visible_assignments.count { |a| a.status == "completed" }
    }
  end
end
