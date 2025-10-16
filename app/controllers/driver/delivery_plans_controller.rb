# frozen_string_literal: true

module Driver
  class DeliveryPlansController < ApplicationController
    layout "driver"
    before_action :authenticate_user!
    before_action :set_delivery_plan, only: [ :show, :update_position, :start, :finish, :abort ]
    after_action :verify_authorized

    def index
      authorize [ :driver, DeliveryPlan ]

      base_scope = policy_scope([ :driver, DeliveryPlan ])
                    .where(driver_id: current_user.id)
                    .includes(:deliveries, :driver)

      @q = base_scope.ransack(params[:q])
      @delivery_plans = @q.result
                          .order(year: :desc, week: :desc)
                          .page(params[:page])

      respond_to do |format|
        format.html
        format.json do
          render json: {
            ok: true,
            plans: @delivery_plans.map { |plan| plan_summary_json(plan) }
          }
        end
      end
    end

    def show
      authorize [ :driver, @delivery_plan ]

      @assignments = @delivery_plan.delivery_plan_assignments
                                   .includes(delivery: [ :order, :delivery_address, :delivery_items ])
                                   .order(:stop_order)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            ok: true,
            data: plan_detail_json(@delivery_plan, @assignments)
          }
        end
      end
    end

    def update_position
      authorize [ :driver, @delivery_plan ]

      position_params = params.require(:position).permit(
        :lat, :lng, :speed, :heading, :accuracy, :at
      )

      @delivery_plan.update!(
        current_lat: position_params[:lat],
        current_lng: position_params[:lng],
        current_speed: position_params[:speed],
        current_heading: position_params[:heading],
        current_accuracy: position_params[:accuracy],
        last_seen_at: position_params[:at] || Time.current
      )

      render json: {
        ok: true,
        last_seen_at: @delivery_plan.last_seen_at.iso8601
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def start
      authorize [ :driver, @delivery_plan ]
      @delivery_plan.start!
      render json: { ok: true, status: @delivery_plan.status, message: "Plan iniciado" }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def finish
      authorize [ :driver, @delivery_plan ]
      @delivery_plan.finish!
      render json: { ok: true, status: @delivery_plan.status, message: "Plan finalizado" }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def abort
      authorize [ :driver, @delivery_plan ]
      @delivery_plan.abort!
      render json: { ok: true, status: @delivery_plan.status, message: "Plan abortado" }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def set_delivery_plan
      @delivery_plan = DeliveryPlan.find(params[:id])
    end

    def plan_summary_json(plan)
      {
        id: plan.id,
        week: plan.week,
        year: plan.year,
        truck: plan.truck,
        driver: plan.driver&.name,
        status: plan.status,
        last_seen_at: plan.last_seen_at&.iso8601,
        deliveries_count: plan.deliveries.count
      }
    end

    def plan_detail_json(plan, assignments)
      {
        plan: {
          id: plan.id,
          week: plan.week,
          year: plan.year,
          truck: plan.truck,
          driver_id: plan.driver_id,
          driver_name: plan.driver&.name,
          status: plan.status,
          last_seen_at: plan.last_seen_at&.iso8601,
          current_lat: plan.current_lat,
          current_lng: plan.current_lng,
          current_speed: plan.current_speed,
          current_heading: plan.current_heading,
          current_accuracy: plan.current_accuracy,
          lock_version: plan.lock_version
        },
        assignments: assignments.map { |a| assignment_json(a) },
        progress: {
          completed: assignments.count(&:completed?),
          en_route: assignments.count(&:en_route?),
          pending: assignments.count(&:pending?),
          total: assignments.count
        }
      }
    end

    def assignment_json(assignment)
      delivery = assignment.delivery
      address = delivery.delivery_address

      {
        id: assignment.id,
        delivery_id: delivery.id,
        stop_order: assignment.stop_order,
        status: assignment.status,
        started_at: assignment.started_at&.iso8601,
        completed_at: assignment.completed_at&.iso8601,
        driver_notes: assignment.driver_notes,
        lock_version: assignment.lock_version,
        delivery: {
          id: delivery.id,
          status: delivery.status,
          delivery_date: delivery.delivery_date&.iso8601,
          contact_name: delivery.contact_name,
          contact_phone: delivery.contact_phone,
          delivery_notes: delivery.delivery_notes,
          delivery_time_preference: delivery.delivery_time_preference,
          order_number: delivery.order&.number,
          client_name: delivery.order&.client&.name,
          address: address ? {
            text: address.address,
            description: address.description,
            lat: address.latitude,
            lng: address.longitude,
            plus_code: address.plus_code
          } : nil,
          items: delivery.delivery_items.map { |item|
            {
              id: item.id,
              product: item.order_item&.product,
              quantity: item.quantity,
              notes: item.notes,
              order_item_notes: item.order_item&.notes
            }
          }
        }
      }
    end
  end
end
