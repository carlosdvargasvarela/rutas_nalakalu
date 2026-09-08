// app/javascript/controllers/public_tracking_waiting_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

export default class extends Controller {
  static values = { planId: Number, deliveryId: Number };

  connect() {
    this.subscription = subscribeToDeliveryPlan(this.planIdValue, (data) => {
      if (data.type !== "assignment_update") return;
      if (data.delivery_id !== this.deliveryIdValue) return;
      if (data.status !== "in_route") return;

      // El conductor arrancó esta parada: recargamos para pasar al mapa en
      // vivo (el servidor decide el stage — no duplicamos esa lógica aquí).
      window.location.reload();
    });
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe();
  }
}
