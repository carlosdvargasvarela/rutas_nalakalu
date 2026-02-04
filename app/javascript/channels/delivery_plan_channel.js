// app/javascript/channels/delivery_plan_channel.js
import consumer from "./consumer";

export function subscribeToDeliveryPlan(deliveryPlanId, callback) {
  return consumer.subscriptions.create(
    { channel: "DeliveryPlanChannel", delivery_plan_id: deliveryPlanId },
    {
      received(data) {
        callback(data);
      },
    },
  );
}
