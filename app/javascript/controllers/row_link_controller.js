// app/javascript/controllers/row_link_controller.js
// Hace que toda la fila de la tabla sea clickeable
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.style.cursor = "pointer";
  }

  navigate(e) {
    // Solo navegar si el click no fue en un botón/link/dropdown
    if (e.target.closest("a, button, .dropdown, form")) return;
    const href = this.element.dataset.href;
    if (href) window.location.href = href;
  }

  stopPropagation(e) {
    e.stopPropagation();
  }
}
