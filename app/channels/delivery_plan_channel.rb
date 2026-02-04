# app/channels/delivery_plan_channel.rb
class DeliveryPlanChannel < ApplicationCable::Channel
  def subscribed
    @delivery_plan = DeliveryPlan.find(params[:delivery_plan_id])
    stream_for @delivery_plan
  end

  def unsubscribed
    # cleanup opcional
  end
end
