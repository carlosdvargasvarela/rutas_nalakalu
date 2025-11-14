// app/javascript/controllers/sortable_controller.js
import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

export default class extends Controller {
  static targets = ["list"];
  static values = { url: String };

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      dragClass: "sortable-drag",
      draggable: ".stop-group-header",

      onEnd: () => {
        this.updateStopOrder();
      },
    });
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }

  updateStopOrder() {
    // Obtener todos los headers de grupo en el nuevo orden
    const headers = this.listTarget.querySelectorAll(".stop-group-header");
    const stopOrders = {};
    let currentStop = 1;

    headers.forEach((header) => {
      // Dentro de cada header, buscar todas las filas con data-assignment-id
      const groupRows = header.querySelectorAll("tr[data-assignment-id]");

      groupRows.forEach((row) => {
        const assignmentId = row.dataset.assignmentId;
        stopOrders[assignmentId] = currentStop;
      });

      currentStop++;
    });

    console.log("stopOrders a enviar:", stopOrders);
    this.sendUpdateToServer(stopOrders);
  }

  sendUpdateToServer(stopOrders) {
    const csrfToken = document.querySelector("[name='csrf-token']").content;

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        Accept: "application/json",
      },
      body: JSON.stringify({ stop_orders: stopOrders }),
    })
      .then((response) => {
        if (response.ok) {
          window.location.reload();
        } else {
          console.error("Error al actualizar el orden");
          alert("Error al actualizar el orden de las paradas");
        }
      })
      .catch((error) => {
        console.error("Error:", error);
        alert("Error de conexión al actualizar el orden");
      });
  }
}
