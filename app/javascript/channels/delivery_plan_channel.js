// app/javascript/channels/delivery_plan_channel.js
import consumer from "channels/consumer";

export function subscribeToDeliveryPlan(deliveryPlanId, callback, onConnectionChange) {
  return consumer.subscriptions.create(
    {
      channel: "DeliveryPlanChannel",
      delivery_plan_id: deliveryPlanId,
    },
    {
      connected() {
        console.log("✅ Canal conectado:", deliveryPlanId);
        if (onConnectionChange) onConnectionChange(true);
      },

      disconnected() {
        console.log("❌ Canal desconectado");
        if (onConnectionChange) onConnectionChange(false);
      },

      received(data) {
        console.log("📡 Datos recibidos:", data);
        callback(data);
      },
    },
  );
}
