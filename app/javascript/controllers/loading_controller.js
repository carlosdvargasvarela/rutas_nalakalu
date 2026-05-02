// app/javascript/controllers/loading_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["searchInput", "deliveryCard", "deliveryList"];
  static values = { planId: Number };

  connect() {
    // Restaurar búsqueda si hay valor en el input al cargar
    if (this.hasSearchInputTarget && this.searchInputTarget.value) {
      this._applyFilter(this.searchInputTarget.value);
    }
  }

  // ── Búsqueda en tiempo real (sin reload) ──────────────────────────────────
  filterDeliveries(event) {
    this._applyFilter(event.target.value.trim().toLowerCase());
  }

  _applyFilter(term) {
    let visibleCount = 0;

    this.deliveryCardTargets.forEach((card) => {
      const clientName = (card.dataset.clientName || "").toLowerCase();
      const orderNumber = (card.dataset.orderNumber || "").toLowerCase();
      const matches =
        !term || clientName.includes(term) || orderNumber.includes(term);

      card.style.display = matches ? "" : "none";
      if (matches) visibleCount++;
    });

    this._toggleEmptyState(visibleCount === 0);
  }

  _toggleEmptyState(isEmpty) {
    const existing = this.element.querySelector("[data-empty-state]");
    if (isEmpty && !existing) {
      const el = document.createElement("div");
      el.setAttribute("data-empty-state", "");
      el.className = "text-center py-5 text-muted";
      el.innerHTML = `
        <i class="bi bi-search" style="font-size:2.5rem; color:#cbd5e1;"></i>
        <p class="mt-3 mb-0">Sin resultados para tu búsqueda.</p>
      `;
      this.deliveryListTarget.appendChild(el);
    } else if (!isEmpty && existing) {
      existing.remove();
    }
  }

  // ── Scroll suave a entrega ────────────────────────────────────────────────
  scrollToDelivery(event) {
    const deliveryId = event.params.deliveryId;
    const el = document.getElementById(`delivery_${deliveryId}`);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.classList.add("highlight-flash");
      setTimeout(() => el.classList.remove("highlight-flash"), 2000);
    }
  }

  // ── Confirmación acción masiva ────────────────────────────────────────────
  confirmMassAction(event) {
    const { action, count } = event.params;
    const messages = {
      mark_all_loaded: `¿Marcar ${count} productos como cargados?`,
      reset_all: `¿Resetear el estado de carga de ${count} productos?`,
    };
    if (!confirm(messages[action] || "¿Confirmar acción?")) {
      event.preventDefault();
    }
  }
}
