import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

export default class extends Controller {
  static targets = ["list"];
  static values = { url: String };

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      animation: 150,
      handle: ".drag-handle",
      draggable: ".stop-group",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      onEnd: () => this.updateStopOrder(),
    });
  }

  disconnect() {
    this.sortable?.destroy();
  }

  updateStopOrder() {
    const stopOrders = {};
    let stopNumber = 1;

    this.listTarget.querySelectorAll(".stop-group").forEach((group) => {
      group.querySelectorAll("[data-assignment-id]").forEach((item) => {
        stopOrders[item.dataset.assignmentId] = stopNumber;
      });
      stopNumber++;
    });

    // Actualizar badges visualmente sin reload
    this.listTarget.querySelectorAll(".stop-group").forEach((group, idx) => {
      const badge = group.querySelector(".stop-number");
      if (badge) badge.textContent = idx + 1;

      const title = group.querySelector(".fw-semibold.text-dark.small");
      if (title && title.textContent.startsWith("Parada")) {
        title.textContent = `Parada ${idx + 1}`;
      }
    });

    this.sendUpdate(stopOrders);
  }

  sendUpdate(stopOrders) {
    const csrf = document.querySelector("[name='csrf-token']").content;

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf,
        Accept: "application/json",
      },
      body: JSON.stringify({ stop_orders: stopOrders }),
    }).catch(() => this.showError());
  }

  showError() {
    const toast = document.createElement("div");
    toast.className =
      "alert alert-danger position-fixed bottom-0 end-0 m-3 shadow";
    toast.style.zIndex = 9999;
    toast.innerHTML = `<i class="bi bi-exclamation-triangle me-2"></i>Error al guardar el orden`;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
  }
}
