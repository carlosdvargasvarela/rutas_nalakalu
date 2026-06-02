// app/javascript/controllers/toast_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    message: String,
    type: { type: String, default: "info" },
    duration: { type: Number, default: 4000 },
  };

  connect() {
    if (this.messageValue) this.show();
  }

  show() {
    const container = this._getOrCreateContainer();
    const toast = this._createToast();
    container.appendChild(toast);

    requestAnimationFrame(() => requestAnimationFrame(() => toast.classList.add("show")));

    if (this.durationValue > 0) {
      setTimeout(() => this._hide(toast), this.durationValue);
    }
  }

  close(event) {
    const toast = event.currentTarget.closest(".toast-notification");
    if (toast) this._hide(toast);
  }

  _getOrCreateContainer() {
    let container = document.getElementById("toast-container");
    if (!container) {
      container = document.createElement("div");
      container.id = "toast-container";
      document.body.appendChild(container);
    }
    return container;
  }

  _createToast() {
    const toast = document.createElement("div");
    toast.className = `toast-notification toast-${this.typeValue}`;
    toast.innerHTML = `
      <div class="toast-content">
        <i class="bi ${this._icon()} toast-icon"></i>
        <span class="toast-message">${this.messageValue}</span>
      </div>
      <button type="button" class="toast-close" data-action="click->toast#close">
        <i class="bi bi-x-lg"></i>
      </button>
    `;
    return toast;
  }

  _icon() {
    return {
      success: "bi-check-circle-fill",
      error:   "bi-exclamation-circle-fill",
      warning: "bi-exclamation-triangle-fill",
      info:    "bi-info-circle-fill",
    }[this.typeValue] || "bi-info-circle-fill";
  }

  _hide(toast) {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 300);
  }
}
