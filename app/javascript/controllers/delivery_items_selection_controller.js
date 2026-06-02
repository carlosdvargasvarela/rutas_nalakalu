// app/javascript/controllers/delivery_items_selection_controller.js
import { Controller } from "@hotwired/stimulus";
import { confirmDialog } from "confirm_dialog";

export default class extends Controller {
  static targets = ["checkbox", "bulkButton", "count"];

  connect() {
    this.updateUI();
    this._onDropdownShow = (e) => {
      const tr = e.target.closest("tr");
      if (tr) tr.classList.add("dropdown-row-open");
    };
    this._onDropdownHide = (e) => {
      const tr = e.target.closest("tr");
      if (tr) tr.classList.remove("dropdown-row-open");
    };
    this.element.addEventListener("show.bs.dropdown", this._onDropdownShow);
    this.element.addEventListener("hidden.bs.dropdown", this._onDropdownHide);
  }

  disconnect() {
    this.element.removeEventListener("show.bs.dropdown", this._onDropdownShow);
    this.element.removeEventListener("hidden.bs.dropdown", this._onDropdownHide);
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = event.target.checked;
    });
    this.updateUI();
  }

  updateUI() {
    const selectedCount = this.checkboxTargets.filter((c) => c.checked).length;

    this.bulkButtonTargets.forEach((btn) => {
      btn.disabled = selectedCount === 0;
    });

    if (this.hasCountTarget) {
      this.countTarget.textContent = selectedCount;
    }
  }

  // ─── Acciones bulk con modal ──────────────────────────────────────────────────

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

  // ─── Acciones bulk directas ───────────────────────────────────────────────────

  async bulkConfirm(event) {
    const btn = event.currentTarget;
    const ids = this._selectedIds();
    if (ids.length === 0) return;
    if (!await confirmDialog(`¿Confirmar ${ids.length} producto(s) seleccionado(s)?`)) return;
    this._submitBulkAction(btn.dataset.url, btn.dataset.deliveryId, ids);
  }

  async bulkDeliver(event) {
    const btn = event.currentTarget;
    const ids = this._selectedIds();
    if (ids.length === 0) return;
    if (!await confirmDialog(`¿Marcar ${ids.length} producto(s) como entregado(s)?`)) return;
    this._submitBulkAction(btn.dataset.url, btn.dataset.deliveryId, ids);
  }

  async bulkDeconfirm(event) {
    const btn = event.currentTarget;
    const ids = this._selectedIds();
    if (ids.length === 0) return;
    if (!await confirmDialog(`¿Desconfirmar ${ids.length} producto(s) seleccionado(s)?`, { danger: true })) return;
    this._submitBulkAction(btn.dataset.url, btn.dataset.deliveryId, ids);
  }

  async bulkCancel(event) {
    const btn = event.currentTarget;
    const ids = this._selectedIds();
    if (ids.length === 0) return;
    if (!await confirmDialog(`¿Cancelar ${ids.length} producto(s) seleccionado(s)?`, { danger: true })) return;
    this._submitBulkAction(btn.dataset.url, btn.dataset.deliveryId, ids);
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

  // Envía PATCH con delivery_id e item_ids directamente (sin modal)
  _submitBulkAction(url, deliveryId, ids) {
    const form = document.createElement("form");
    form.method = "POST";
    form.action = url;

    const appendHidden = (name, value) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.appendChild(input);
    };

    const csrf = document.querySelector('meta[name="csrf-token"]');
    if (csrf) appendHidden("authenticity_token", csrf.content);
    appendHidden("_method", "patch");
    appendHidden("delivery_id", deliveryId);
    appendHidden("item_ids", ids.join(","));

    document.body.appendChild(form);
    form.requestSubmit();
    form.remove();
  }
}
