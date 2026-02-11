// app/javascript/controllers/address_validator_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["descriptionInput", "statusBadge"];

  connect() {
    this.validateAddress();
  }

  validateAddress() {
    const description = this.descriptionInputTarget.value.trim();
    const isValid = this.isDescriptionValid(description);

    if (isValid) {
      this.statusBadgeTarget.textContent = "✓ Válido";
      this.statusBadgeTarget.className = "badge bg-success text-white";
      this.descriptionInputTarget.classList.remove("is-invalid");
      this.descriptionInputTarget.classList.add("is-valid");
    } else {
      this.statusBadgeTarget.textContent = "⚠ Incompleto";
      this.statusBadgeTarget.className = "badge bg-warning text-dark";
      this.descriptionInputTarget.classList.remove("is-valid");
      this.descriptionInputTarget.classList.add("is-invalid");
    }
  }

  isDescriptionValid(text) {
    if (text.length < 10) return false;
    if (text.includes("http://") || text.includes("https://")) return false;
    return true;
  }
}
