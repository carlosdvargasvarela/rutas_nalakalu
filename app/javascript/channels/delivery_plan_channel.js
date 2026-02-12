// app/javascript/channels/delivery_plan_channel.js
import consumer from "./consumer"

export function subscribeToDeliveryPlan(deliveryPlanId, callback) {
  return consumer.subscriptions.create(
    { 
      channel: "DeliveryPlanChannel", 
      delivery_plan_id: deliveryPlanId 
    },
    {
      connected() {
        console.log(`✅ Conectado al canal del plan: ${deliveryPlanId}`)
      },
      disconnected() {
        console.log("❌ Desconectado del canal")
      },
      received(data) {
        callback(data)
      }
    }
  )
}