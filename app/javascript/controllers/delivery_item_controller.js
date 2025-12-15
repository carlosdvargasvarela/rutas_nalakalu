// app/javascript/controllers/delivery_item_controller.js
import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["badge", "buttons", "status"];
  static values = {
    itemId: Number,
    deliveryId: Number,
    status: String,
  };

  connect() {
    console.log(
      `DeliveryItem controller connected for item ${this.itemIdValue}`
    );
  }

  // Marcar como cargado con feedback visual
  async markLoaded(event) {
    event.preventDefault();
    this.disableButtons();
    this.showLoadingState("loaded");

    try {
      const response = await this.submitAction(
        event.currentTarget.href,
        "POST"
      );
      if (response.ok) {
        this.showSuccessState("loaded");
        this.dispatchUpdateEvent("loaded");
      } else {
        this.showErrorState();
      }
    } catch (error) {
      console.error("Error marking as loaded:", error);
      this.showErrorState();
    }
  }

  // Marcar como sin cargar
  async markUnloaded(event) {
    event.preventDefault();
    this.disableButtons();
    this.showLoadingState("unloaded");

    try {
      const response = await this.submitAction(
        event.currentTarget.href,
        "POST"
      );
      if (response.ok) {
        this.showSuccessState("unloaded");
        this.dispatchUpdateEvent("unloaded");
      } else {
        this.showErrorState();
      }
    } catch (error) {
      console.error("Error marking as unloaded:", error);
      this.showErrorState();
    }
  }

  // Marcar como faltante
  async markMissing(event) {
    event.preventDefault();

    if (!confirm("¿Marcar este producto como faltante?")) {
      return;
    }

    this.disableButtons();
    this.showLoadingState("missing");

    try {
      const response = await this.submitAction(
        event.currentTarget.href,
        "POST"
      );
      if (response.ok) {
        this.showSuccessState("missing");
        this.dispatchUpdateEvent("missing");
      } else {
        this.showErrorState();
      }
    } catch (error) {
      console.error("Error marking as missing:", error);
      this.showErrorState();
    }
  }

  // Enviar acción al servidor
  async submitAction(url, method) {
    const csrfToken = document.querySelector("[name='csrf-token']").content;

    const response = await fetch(url, {
      method: method,
      headers: {
        "X-CSRF-Token": csrfToken,
        Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      },
      credentials: "same-origin",
    });

    // 👇 Procesar Turbo Streams para actualizar múltiples elementos del DOM
    const contentType = response.headers.get("Content-Type") || "";

    if (contentType.includes("turbo-stream")) {
      const html = await response.text();
      Turbo.renderStreamMessage(html);
    }

    return response;
  }

  // Deshabilitar botones durante la acción
  disableButtons() {
    if (this.hasButtonsTarget) {
      const buttons = this.buttonsTarget.querySelectorAll("button, a");
      buttons.forEach((btn) => {
        btn.disabled = true;
        btn.classList.add("disabled");
      });
    }
  }

  // Habilitar botones
  enableButtons() {
    if (this.hasButtonsTarget) {
      const buttons = this.buttonsTarget.querySelectorAll("button, a");
      buttons.forEach((btn) => {
        btn.disabled = false;
        btn.classList.remove("disabled");
      });
    }
  }

  // Mostrar estado de carga
  showLoadingState(action) {
    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML =
        '<span class="spinner-border spinner-border-sm me-1"></span>Procesando...';
      this.badgeTarget.className = "badge bg-info";
    }
  }

  // Mostrar estado de éxito
  showSuccessState(status) {
    this.statusValue = status;
    this.enableButtons();

    if (this.hasBadgeTarget) {
      this.updateBadge(status);
    }

    // Animación de éxito
    this.element.classList.add("flash-success");
    setTimeout(() => this.element.classList.remove("flash-success"), 1000);
  }

  // Mostrar estado de error
  showErrorState() {
    this.enableButtons();

    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML =
        '<i class="bi bi-exclamation-circle me-1"></i>Error';
      this.badgeTarget.className = "badge bg-danger";
    }

    // Animación de error
    this.element.classList.add("flash-error");
    setTimeout(() => {
      this.element.classList.remove("flash-error");
      this.updateBadge(this.statusValue); // Restaurar estado anterior
    }, 2000);
  }

  // Actualizar badge según estado
  updateBadge(status) {
    if (!this.hasBadgeTarget) return;

    const badgeConfig = {
      unloaded: {
        class: "badge bg-secondary",
        html: '<i class="bi bi-circle me-1"></i>Sin Cargar',
      },
      loaded: {
        class: "badge bg-success",
        html: '<i class="bi bi-check-circle-fill me-1"></i>Cargado',
      },
      missing: {
        class: "badge bg-danger",
        html: '<i class="bi bi-exclamation-triangle-fill me-1"></i>Faltante',
      },
    };

    const config = badgeConfig[status] || badgeConfig.unloaded;
    this.badgeTarget.className = config.class;
    this.badgeTarget.innerHTML = config.html;
  }

  // Disparar evento personalizado para actualizar otros componentes
  dispatchUpdateEvent(status) {
    const event = new CustomEvent("delivery-item:updated", {
      detail: {
        itemId: this.itemIdValue,
        deliveryId: this.deliveryIdValue,
        status: status,
      },
      bubbles: true,
    });
    this.element.dispatchEvent(event);
  }
}
