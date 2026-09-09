import { Controller } from "@hotwired/stimulus";

// Fills the hidden delivery_address fields from the data-* attributes of the
// chosen <option>, mirroring what address-autocomplete does after a map pick.
export default class extends Controller {
  static targets = [
    "select", "address", "description", "latitude", "longitude", "plusCode", "editVendorLink",
    "contactName", "contactPhone", "contactChips", "contactChipsList",
  ];
  static values = {urlTemplate: String};

  fill() {
    const option = this.selectTarget.selectedOptions[0];
    if (!option || !option.dataset.address) {
      this.editVendorLinkTarget.classList.add("d-none");
      this._hideContactChips();
      return;
    }

    this.addressTarget.value = option.dataset.address || "";
    this.descriptionTarget.value = option.dataset.description || "";
    this.latitudeTarget.value = option.dataset.latitude || "";
    this.longitudeTarget.value = option.dataset.longitude || "";
    this.plusCodeTarget.value = option.dataset.plusCode || "";

    // Solo rellena el responsable si el usuario no lo ha editado a mano.
    if (this.hasContactNameTarget && !this.contactNameTarget.value.trim() && option.dataset.contactName) {
      this.contactNameTarget.value = option.dataset.contactName;
      this.contactNameTarget.dispatchEvent(new Event("input", {bubbles: true}));
    }
    if (this.hasContactPhoneTarget && !this.contactPhoneTarget.value.trim() && option.dataset.contactPhone) {
      this.contactPhoneTarget.value = option.dataset.contactPhone;
      this.contactPhoneTarget.dispatchEvent(new Event("input", {bubbles: true}));
    }

    this._renderContactChips(option.dataset.contacts);

    if (option.dataset.vendorId) {
      this.editVendorLinkTarget.href = this.urlTemplateValue.replace("__ID__", option.dataset.vendorId);
      this.editVendorLinkTarget.classList.remove("d-none");
    } else {
      this.editVendorLinkTarget.classList.add("d-none");
    }
  }

  selectContact(event) {
    const btn = event.currentTarget;
    if (this.hasContactNameTarget) {
      this.contactNameTarget.value = btn.dataset.name || "";
      this.contactNameTarget.dispatchEvent(new Event("input", {bubbles: true}));
    }
    if (this.hasContactPhoneTarget) {
      this.contactPhoneTarget.value = btn.dataset.phone || "";
      this.contactPhoneTarget.dispatchEvent(new Event("input", {bubbles: true}));
    }
    this.contactChipsListTarget.querySelectorAll("button").forEach((b) => {
      b.classList.toggle("btn-primary", b === btn);
      b.classList.toggle("btn-outline-secondary", b !== btn);
    });
  }

  // Varios contactos: se muestran como chips para elegir cuál usar en este
  // mandado (el primero/principal ya se precargó en fill()). Un solo
  // contacto no aporta nada eligiendo, así que no se muestra.
  _renderContactChips(contactsJson) {
    if (!this.hasContactChipsTarget) return;

    let contacts = [];
    try {
      contacts = contactsJson ? JSON.parse(contactsJson) : [];
    } catch {
      contacts = [];
    }

    if (contacts.length < 2) {
      this._hideContactChips();
      return;
    }

    this.contactChipsListTarget.innerHTML = "";
    contacts.forEach((contact, i) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `btn btn-sm ${i === 0 ? "btn-primary" : "btn-outline-secondary"}`;
      btn.dataset.name = contact.name || "";
      btn.dataset.phone = contact.phone || "";
      btn.dataset.action = "click->vendor-address-select#selectContact";
      btn.innerHTML = `<i class="bi bi-person me-1"></i>${this._esc(contact.name)}` +
        (contact.phone ? ` <span class="opacity-75 ms-1">· ${this._esc(contact.phone)}</span>` : "");
      this.contactChipsListTarget.appendChild(btn);
    });
    this.contactChipsTarget.classList.remove("d-none");
  }

  _hideContactChips() {
    if (this.hasContactChipsTarget) this.contactChipsTarget.classList.add("d-none");
  }

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
