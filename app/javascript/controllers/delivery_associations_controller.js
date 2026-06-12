// app/javascript/controllers/delivery_associations_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "addForm",
    "orderNumberInput",
    "propagatePanel",
    "propagateChevron",
    "fieldCheckbox",
    "deliveryCheckbox",
    "propagateResult",
    "propagateBtn",
  ];

  static values = { propagateUrl: String };

  toggleAddForm(event) {
    event.preventDefault();
    if (!this.hasAddFormTarget) return;
    const willShow = this.addFormTarget.classList.contains("d-none");
    this.addFormTarget.classList.toggle("d-none", !willShow);
    if (willShow && this.hasOrderNumberInputTarget) {
      this.orderNumberInputTarget.focus();
    }
  }

  togglePropagatePanel(event) {
    event.preventDefault();
    if (!this.hasPropagatePanelTarget) return;
    const willShow = this.propagatePanelTarget.classList.contains("d-none");
    this.propagatePanelTarget.classList.toggle("d-none", !willShow);
    if (this.hasPropagateChevronTarget) {
      this.propagateChevronTarget.style.transform = willShow ? "rotate(180deg)" : "";
    }
  }

  async propagate(event) {
    event.preventDefault();

    const fields = this.fieldCheckboxTargets
      .filter((cb) => cb.checked)
      .map((cb) => cb.value);

    const deliveryIds = this.deliveryCheckboxTargets
      .filter((cb) => cb.checked)
      .map((cb) => cb.value);

    if (fields.length === 0) {
      this._showResult("error", "Selecciona al menos un campo.");
      return;
    }
    if (deliveryIds.length === 0) {
      this._showResult("error", "Selecciona al menos una entrega.");
      return;
    }

    if (this.hasPropagateBtnTarget) this.propagateBtnTarget.disabled = true;

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;

    try {
      const resp = await fetch(this.propagateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf,
        },
        body: JSON.stringify({ fields, delivery_ids: deliveryIds }),
      });

      if (resp.ok) {
        const data = await resp.json();
        this._showResult("success", `Cambios propagados a ${data.updated_count} entrega(s).`);
      } else {
        const data = await resp.json().catch(() => ({}));
        this._showResult("error", data.error || "Error al propagar cambios.");
      }
    } catch (_e) {
      this._showResult("error", "Error de conexion. Intenta de nuevo.");
    } finally {
      if (this.hasPropagateBtnTarget) this.propagateBtnTarget.disabled = false;
    }
  }

  _showResult(type, message) {
    if (!this.hasPropagateResultTarget) return;
    const el = this.propagateResultTarget;
    const icon = type === "success" ? "check-circle" : "exclamation-triangle";
    el.className = `small mb-2 ${type === "success" ? "text-success" : "text-danger"}`;
    el.innerHTML = `<i class="bi bi-${icon} me-1"></i>${message}`;
    el.classList.remove("d-none");
    if (type === "success") {
      setTimeout(() => el.classList.add("d-none"), 5000);
    }
  }
}
