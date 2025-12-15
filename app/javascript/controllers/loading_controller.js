// app/javascript/controllers/loading_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "planProgress",
    "planPercentage",
    "planBadge",
    "deliveryCard",
  ];
  static values = {
    planId: Number,
  };

  connect() {
    console.log("Loading controller connected");
    this.setupTurboStreamListeners();
  }

  setupTurboStreamListeners() {
    // Escuchar eventos de Turbo Stream para actualizar UI
    document.addEventListener("turbo:before-stream-render", (event) => {
      console.log("Turbo stream received:", event.detail);
    });
  }

  // Actualizar progreso del plan
  updatePlanProgress(percentage, status) {
    if (this.hasPlanProgressTarget) {
      this.planProgressTarget.style.width = `${percentage}%`;
      this.planProgressTarget.setAttribute("aria-valuenow", percentage);
      this.planProgressTarget.textContent = `${percentage}%`;
    }

    if (this.hasPlanPercentageTarget) {
      this.planPercentageTarget.textContent = `${percentage}%`;
    }

    if (this.hasPlanBadgeTarget) {
      this.updateBadge(this.planBadgeTarget, status);
    }
  }

  // Actualizar badge de estado
  updateBadge(element, status) {
    // Remover clases anteriores
    element.classList.remove(
      "bg-secondary",
      "bg-success",
      "bg-danger",
      "bg-warning",
      "text-dark"
    );

    // Agregar clase según estado
    switch (status) {
      case "empty":
      case "unloaded":
        element.classList.add("bg-secondary");
        element.innerHTML = '<i class="bi bi-circle me-1"></i>Sin Cargar';
        break;
      case "all_loaded":
      case "loaded":
        element.classList.add("bg-success");
        element.innerHTML =
          '<i class="bi bi-check-circle-fill me-1"></i>Cargado';
        break;
      case "some_missing":
      case "missing":
        element.classList.add("bg-danger");
        element.innerHTML =
          '<i class="bi bi-exclamation-triangle-fill me-1"></i>Faltante';
        break;
      case "partial":
        element.classList.add("bg-warning", "text-dark");
        element.innerHTML = '<i class="bi bi-hourglass-split me-1"></i>Parcial';
        break;
    }
  }

  // Filtrar entregas en tiempo real (búsqueda local)
  filterDeliveries(event) {
    const searchTerm = event.target.value.toLowerCase();

    this.deliveryCardTargets.forEach((card) => {
      const clientName = card.dataset.clientName?.toLowerCase() || "";
      const orderNumber = card.dataset.orderNumber?.toLowerCase() || "";

      if (clientName.includes(searchTerm) || orderNumber.includes(searchTerm)) {
        card.style.display = "";
      } else {
        card.style.display = "none";
      }
    });
  }

  // Scroll suave a una entrega específica
  scrollToDelivery(event) {
    const deliveryId = event.params.deliveryId;
    const element = document.getElementById(`delivery_${deliveryId}`);

    if (element) {
      element.scrollIntoView({ behavior: "smooth", block: "center" });
      element.classList.add("highlight-flash");
      setTimeout(() => element.classList.remove("highlight-flash"), 2000);
    }
  }

  // Confirmar acción masiva
  confirmMassAction(event) {
    const action = event.params.action;
    const count = event.params.count;

    const messages = {
      mark_all_loaded: `¿Estás seguro de marcar ${count} productos como cargados?`,
      reset_all: `¿Estás seguro de resetear el estado de carga de ${count} productos?`,
    };

    if (!confirm(messages[action])) {
      event.preventDefault();
    }
  }

  // Mostrar/ocultar detalles de entrega
  toggleDeliveryDetails(event) {
    const deliveryId = event.params.deliveryId;
    const detailsElement = document.getElementById(
      `delivery_details_${deliveryId}`
    );

    if (detailsElement) {
      detailsElement.classList.toggle("d-none");
      event.currentTarget
        .querySelector("i")
        .classList.toggle("bi-chevron-down");
      event.currentTarget.querySelector("i").classList.toggle("bi-chevron-up");
    }
  }
}
