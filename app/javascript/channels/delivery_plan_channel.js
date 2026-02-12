// app/javascript/channels/delivery_plan_channel.js
import consumer from "./consumer";

export function subscribeToDeliveryPlan(deliveryPlanId, callback) {
  return consumer.subscriptions.create(
    {
      channel: "DeliveryPlanChannel",
      delivery_plan_id: deliveryPlanId,
    },
    {
      connected() {
        console.log("✅ Canal conectado:", deliveryPlanId);
      },

      disconnected() {
        console.log("❌ Canal desconectado");
      },

      received(data) {
        console.log("📡 Datos recibidos:", data);
        callback(data);
      },
    },
  );
}
