// app/javascript/controllers/address_validator_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["submit", "addressInput", "errorMessage"];

  validateBeforeSubmit(event) {
    const lat = document.querySelector(
      "[data-address-autocomplete-target='lat']",
    )?.value;
    const lng = document.querySelector(
      "[data-address-autocomplete-target='lng']",
    )?.value;
    const description = document.querySelector(
      "textarea[name*='description']",
    )?.value;

    if (!lat || !lng || parseFloat(lat) === 0 || parseFloat(lng) === 0) {
      event.preventDefault();
      this._showError(
        "Debes seleccionar una ubicación válida en el mapa antes de guardar.",
      );
      return;
    }

    if (!description || description.trim().length < 5) {
      const fallback = this.buildFallbackDescription();
      document.querySelector("textarea[name*='description']").value = fallback;
    }

    this._clearError();
  }

  buildFallbackDescription() {
    const details = document.querySelector(
      "[data-address-autocomplete-target='geoDetails']",
    )?.innerText;

    if (details && details.trim().length > 10) {
      return `Sin referencias del vendedor. Ubicación aproximada: ${details.replace(/[\n\r]+/g, ", ").trim()}`;
    }

    return "Sin referencias del vendedor.";
  }

  _showError(message) {
    let errorEl = this.element.querySelector("[data-validator-error]");
    if (!errorEl) {
      errorEl = document.createElement("div");
      errorEl.setAttribute("data-validator-error", "true");
      errorEl.className =
        "alert alert-danger mt-3 d-flex align-items-center gap-2";
      errorEl.innerHTML = `<i class="bi bi-exclamation-triangle-fill"></i><span></span>`;
      if (this.hasSubmitTarget) {
        this.submitTarget.closest(".card-body")?.prepend(errorEl);
      } else {
        this.element.prepend(errorEl);
      }
    }
    errorEl.querySelector("span").textContent = message;
    errorEl.style.display = "flex";
    errorEl.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  _clearError() {
    this.element.querySelector("[data-validator-error]")?.remove();
  }
}
