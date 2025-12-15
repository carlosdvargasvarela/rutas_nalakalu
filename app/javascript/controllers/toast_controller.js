// app/javascript/controllers/toast_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    message: String,
    type: String, // success, error, warning, info
    duration: { type: Number, default: 3000 },
  };

  connect() {
    this.show();
  }

  show() {
    // Crear toast element
    const toast = this.createToast();
    document.body.appendChild(toast);

    // Mostrar con animación
    setTimeout(() => toast.classList.add("show"), 100);

    // Auto-ocultar
    setTimeout(() => this.hide(toast), this.durationValue);
  }

  createToast() {
    const toast = document.createElement("div");
    toast.className = `toast-notification toast-${this.typeValue}`;

    const icon = this.getIcon(this.typeValue);

    toast.innerHTML = `
      <div class="toast-content">
        <i class="bi ${icon} me-2"></i>
        <span>${this.messageValue}</span>
      </div>
      <button type="button" class="toast-close" data-action="click->toast#close">
        <i class="bi bi-x-lg"></i>
      </button>
    `;

    return toast;
  }

  getIcon(type) {
    const icons = {
      success: "bi-check-circle-fill",
      error: "bi-exclamation-circle-fill",
      warning: "bi-exclamation-triangle-fill",
      info: "bi-info-circle-fill",
    };
    return icons[type] || icons.info;
  }

  hide(toast) {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 300);
  }

  close(event) {
    const toast = event.currentTarget.closest(".toast-notification");
    this.hide(toast);
  }
}
