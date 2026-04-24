// app/javascript/controllers/delivery_items_selection_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "bulkButton", "count"];

  connect() {
    this.updateUI();
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = event.target.checked;
    });
    this.updateUI();
  }

  updateUI() {
    const selectedCount = this.checkboxTargets.filter((c) => c.checked).length;

    if (this.hasBulkButtonTarget) {
      this.bulkButtonTarget.disabled = selectedCount === 0;
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = selectedCount;
    }
  }

  // ─── Acciones bulk ───────────────────────────────────────────────────────────

  prepareReschedule(event) {
    const selectedIds = this._selectedIds();
    if (selectedIds.length === 0) return;
    this._openModal(event.currentTarget.dataset.url, selectedIds);
  }

  prepareSalaPickup(event) {
    const btn = event.currentTarget;
    const preselected = this._preselectedIds(btn);
    this._applyPreselection(preselected);
    const ids = preselected.length > 0 ? preselected : this._selectedIds();
    if (ids.length === 0) return;
    this._openModal(btn.dataset.url, ids);
  }

  prepareServiceCase(event) {
    const btn = event.currentTarget;
    const preselected = this._preselectedIds(btn);
    this._applyPreselection(preselected);
    const ids = preselected.length > 0 ? preselected : this._selectedIds();
    if (ids.length === 0) return;
    this._openModal(btn.dataset.url, ids);
  }

  // ─── Privados ────────────────────────────────────────────────────────────────

  _selectedIds() {
    return this.checkboxTargets.filter((c) => c.checked).map((c) => c.value);
  }

  // Lee data-preselect-ids del botón y devuelve array de strings
  _preselectedIds(btn) {
    const raw = btn.dataset.preselectIds || "";
    return raw
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean);
  }

  // Marca los checkboxes cuyos values están en ids, desmarca el resto
  _applyPreselection(ids) {
    if (ids.length === 0) return;

    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = ids.includes(checkbox.value);
    });
    this.updateUI();
  }

  // Construye la URL con item_ids y la carga en el turbo-frame "modal"
  _openModal(rawUrl, ids) {
    const url = new URL(rawUrl, window.location.origin);
    url.searchParams.set("item_ids", ids.join(","));

    const modalFrame = document.getElementById("modal");
    if (modalFrame) {
      modalFrame.src = url.toString();
    }
  }
}
