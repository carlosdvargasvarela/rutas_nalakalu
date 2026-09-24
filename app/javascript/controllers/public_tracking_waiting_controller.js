// app/javascript/controllers/public_tracking_waiting_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

export default class extends Controller {
  static values = { planId: Number, deliveryIds: Array };
  static targets = ["connectionBanner"];

  connect() {
    this.subscription = subscribeToDeliveryPlan(
      this.planIdValue,
      (data) => {
        if (data.type !== "assignment_update") return;
        if (!this.deliveryIdsValue.includes(data.delivery_id)) return;

        // Cualquier cambio de estado de la parada (arrancó, se canceló...):
        // recargamos y el servidor decide el stage — no duplicamos esa
        // lógica aquí.
        window.location.reload();
      },
      (isConnected) => this.updateConnectionBanner(isConnected),
    );
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe();
  }

  updateConnectionBanner(isConnected) {
    if (!this.hasConnectionBannerTarget) return;
    this.connectionBannerTarget.hidden = isConnected;
  }
}
