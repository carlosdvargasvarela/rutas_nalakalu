import { Controller } from "@hotwired/stimulus";
import { Modal } from "bootstrap";

// Mantiene una sola instancia de address-autocomplete (un solo mapa) que se
// reutiliza para agregar o editar cualquier dirección de la lista, en vez de
// tener un mapa por dirección.
export default class extends Controller {
  static targets = [
    "list",
    "modal",
    "modalTitle",
    "address",
    "description",
    "latitude",
    "longitude",
    "plusCode",
    "emptyHint",
  ];
  static outlets = ["address-autocomplete"];
  static values = { addresses: Array };

  connect() {
    this.entries = this.addressesValue.map((a) => ({...a}));
    this.editingIndex = null;
    this.render();
  }

  openAdd() {
    this.editingIndex = null;
    this.modalTitleTarget.textContent = "Agregar dirección";
    this.resetModalFields();
    this.showModal();
  }

  openEdit(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const entry = this.entries[index];
    this.editingIndex = index;
    this.modalTitleTarget.textContent = "Editar dirección";
    this.resetModalFields();

    this.addressTarget.value = entry.address || "";
    this.descriptionTarget.value = entry.description || "";
    if (this.hasAddressAutocompleteOutlet && entry.latitude && entry.longitude) {
      this.addressAutocompleteOutlet.updateFromCoords(
        parseFloat(entry.latitude),
        parseFloat(entry.longitude),
      );
    }
    if (this.hasAddressAutocompleteOutlet && this.addressAutocompleteOutlet.hasAddressDisplayTarget) {
      this.addressAutocompleteOutlet.addressDisplayTarget.textContent = entry.address || "";
    }
    this.showModal();
  }

  confirm() {
    if (!this.addressTarget.value) return;

    const entry = {
      id: this.editingIndex !== null ? this.entries[this.editingIndex].id : null,
      address: this.addressTarget.value,
      description: this.descriptionTarget.value,
      latitude: this.latitudeTarget.value,
      longitude: this.longitudeTarget.value,
      plusCode: this.plusCodeTarget.value,
    };

    if (this.editingIndex !== null) {
      this.entries[this.editingIndex] = entry;
    } else {
      this.entries.push(entry);
    }

    this.render();
    Modal.getOrCreateInstance(this.modalTarget).hide();
  }

  remove(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const entry = this.entries[index];

    if (entry.id) {
      entry.destroy = true;
    } else {
      this.entries.splice(index, 1);
    }
    this.render();
  }

  showModal() {
    Modal.getOrCreateInstance(this.modalTarget).show();
  }

  resetModalFields() {
    this.addressTarget.value = "";
    this.descriptionTarget.value = "";
    this.latitudeTarget.value = "";
    this.longitudeTarget.value = "";
    this.plusCodeTarget.value = "";
    if (this.hasAddressAutocompleteOutlet && this.addressAutocompleteOutlet.hasAddressDisplayTarget) {
      this.addressAutocompleteOutlet.addressDisplayTarget.textContent = "";
    }
  }

  render() {
    const visible = this.entries.filter((e) => !e.destroy);
    this.emptyHintTarget.classList.toggle("d-none", visible.length > 0);

    this.listTarget.innerHTML = this.entries.map((entry, i) => this.rowHtml(entry, i)).join("");
  }

  rowHtml(entry, i) {
    const prefix = `vendor[vendor_addresses_attributes][${i}]`;
    const idField = entry.id ? `<input type="hidden" name="${prefix}[id]" value="${entry.id}">` : "";

    if (entry.destroy) {
      return `${idField}<input type="hidden" name="${prefix}[_destroy]" value="1">`;
    }

    return `
      <div class="d-flex justify-content-between align-items-start border rounded p-2 mb-2 bg-white">
        <div class="small">
          <div class="fw-semibold">${this.escape(entry.address) || "(sin dirección)"}</div>
          ${entry.description ? `<div class="text-muted">${this.escape(entry.description)}</div>` : ""}
        </div>
        <div class="d-flex gap-1 flex-shrink-0 ms-2">
          <button type="button" class="btn btn-sm btn-outline-secondary" data-action="vendor-address-list#openEdit" data-index="${i}">
            <i class="bi bi-pencil"></i>
          </button>
          <button type="button" class="btn btn-sm btn-outline-danger" data-action="vendor-address-list#remove" data-index="${i}">
            <i class="bi bi-trash"></i>
          </button>
        </div>
      </div>
      ${idField}
      <input type="hidden" name="${prefix}[address]" value="${this.escape(entry.address)}">
      <input type="hidden" name="${prefix}[description]" value="${this.escape(entry.description)}">
      <input type="hidden" name="${prefix}[latitude]" value="${this.escape(entry.latitude)}">
      <input type="hidden" name="${prefix}[longitude]" value="${this.escape(entry.longitude)}">
      <input type="hidden" name="${prefix}[plus_code]" value="${this.escape(entry.plusCode)}">
    `;
  }

  escape(value) {
    if (value == null) return "";
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
