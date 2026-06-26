// app/javascript/controllers/contact_selector_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "nameField",
    "phoneField",
    "display",
    "addForm",
    "nameInput",
    "phoneInput",
    "primaryInput",
    "saveBtn",
    "error",
    "editForm",
    "editContactId",
    "editNameInput",
    "editPhoneInput",
    "editPrimaryInput",
    "editSaveBtn",
    "editError",
  ];

  static values = { contactsUrl: String };

  // ── Selección ──────────────────────────────────────────────────────────────

  select(event) {
    const btn = event.currentTarget;
    const name = btn.dataset.name || "";
    const phone = btn.dataset.phone || "";

    if (this.hasNameFieldTarget) this.nameFieldTarget.value = name;
    if (this.hasPhoneFieldTarget) this.phoneFieldTarget.value = phone;
    this._updateDisplay(name, phone);
    this._highlightChip(btn);
  }

  // ── Agregar nuevo contacto ─────────────────────────────────────────────────

  toggleForm(event) {
    event.preventDefault();
    if (!this.hasAddFormTarget) return;
    const hidden = this.addFormTarget.classList.contains("d-none");
    this.addFormTarget.classList.toggle("d-none", !hidden);
    // Cerrar edición si estaba abierta
    if (hidden) {
      if (this.hasEditFormTarget) this.editFormTarget.classList.add("d-none");
      if (this.hasNameInputTarget) this.nameInputTarget.focus();
    } else {
      this._clearAddForm();
    }
  }

  async saveContact(event) {
    event.preventDefault();
    if (!this.hasNameInputTarget) return;

    const name = this.nameInputTarget.value.trim();
    if (!name) {
      this._showError("El nombre es obligatorio.");
      return;
    }

    const phone = this.hasPhoneInputTarget ? this.phoneInputTarget.value.trim() : "";
    const isPrimary = this.hasPrimaryInputTarget ? this.primaryInputTarget.checked : false;

    if (this.hasSaveBtnTarget) this.saveBtnTarget.disabled = true;

    try {
      const saved = await this._request(this.contactsUrlValue, "POST", {
        order_contact: { name, phone, is_primary: isPrimary },
      });

      this._appendChip(saved);
      if (this.hasNameFieldTarget) this.nameFieldTarget.value = saved.name;
      if (this.hasPhoneFieldTarget) this.phoneFieldTarget.value = saved.phone || "";
      this._updateDisplay(saved.name, saved.phone || "");
      this._clearAddForm();
      if (this.hasAddFormTarget) this.addFormTarget.classList.add("d-none");
    } catch (e) {
      this._showError(e.message || "No se pudo guardar el contacto.");
    } finally {
      if (this.hasSaveBtnTarget) this.saveBtnTarget.disabled = false;
    }
  }

  // ── Editar contacto existente ──────────────────────────────────────────────

  editContact(event) {
    event.preventDefault();
    const btn = event.currentTarget;

    if (!this.hasEditFormTarget) return;

    // Cerrar el formulario de agregar si está abierto
    if (this.hasAddFormTarget) this.addFormTarget.classList.add("d-none");

    // Pre-rellenar campos
    if (this.hasEditContactIdTarget) this.editContactIdTarget.value = btn.dataset.id;
    if (this.hasEditNameInputTarget) this.editNameInputTarget.value = btn.dataset.name || "";
    if (this.hasEditPhoneInputTarget) this.editPhoneInputTarget.value = btn.dataset.phone || "";
    if (this.hasEditPrimaryInputTarget)
      this.editPrimaryInputTarget.checked = btn.dataset.primary === "true";

    this.editFormTarget.classList.remove("d-none");
    if (this.hasEditNameInputTarget) this.editNameInputTarget.focus();
  }

  async deleteContact(event) {
    event.preventDefault();
    const btn = event.currentTarget;
    const id = btn.dataset.deleteId;
    const group = btn.closest(".btn-group");
    const name = group?.querySelector("[data-action*='select']")?.dataset.name || "";

    if (!confirm(`¿Eliminar el contacto "${name}"?`)) return;

    btn.disabled = true;
    try {
      await this._request(`${this.contactsUrlValue}/${id}`, "DELETE", null);

      // Si este contacto estaba seleccionado, limpiar selección
      if (this.hasNameFieldTarget && this.nameFieldTarget.value === name) {
        this.nameFieldTarget.value = "";
        if (this.hasPhoneFieldTarget) this.phoneFieldTarget.value = "";
        this._updateDisplay("", "");
      }
      // Cerrar panel de edición si estaba editando este contacto
      if (this.hasEditContactIdTarget && this.editContactIdTarget.value === id) {
        if (this.hasEditFormTarget) this.editFormTarget.classList.add("d-none");
        this._clearEditForm();
      }

      group?.remove();
    } catch (e) {
      alert(e.message || "No se pudo eliminar el contacto.");
      btn.disabled = false;
    }
  }

  cancelEdit(event) {
    event.preventDefault();
    if (this.hasEditFormTarget) this.editFormTarget.classList.add("d-none");
    this._clearEditForm();
  }

  async updateContact(event) {
    event.preventDefault();
    if (!this.hasEditContactIdTarget) return;

    const id = this.editContactIdTarget.value;
    if (!id) return;

    const name = this.hasEditNameInputTarget ? this.editNameInputTarget.value.trim() : "";
    if (!name) {
      this._showEditError("El nombre es obligatorio.");
      return;
    }

    const phone = this.hasEditPhoneInputTarget ? this.editPhoneInputTarget.value.trim() : "";
    const isPrimary = this.hasEditPrimaryInputTarget ? this.editPrimaryInputTarget.checked : false;

    if (this.hasEditSaveBtnTarget) this.editSaveBtnTarget.disabled = true;

    // Capturar nombre original antes de modificar el chip
    const originalName = this._originalNameForId(id);

    try {
      const updated = await this._request(`${this.contactsUrlValue}/${id}`, "PATCH", {
        order_contact: { name, phone, is_primary: isPrimary },
      });

      // Si este contacto estaba seleccionado para la entrega, actualizar campos ocultos y display
      if (this.hasNameFieldTarget && this.nameFieldTarget.value === originalName) {
        this.nameFieldTarget.value = updated.name;
        if (this.hasPhoneFieldTarget) this.phoneFieldTarget.value = updated.phone || "";
        this._updateDisplay(updated.name, updated.phone || "");
      }

      // Actualizar el chip correspondiente
      this._updateChip(id, updated);

      this.editFormTarget.classList.add("d-none");
      this._clearEditForm();
    } catch (e) {
      this._showEditError(e.message || "No se pudo actualizar el contacto.");
    } finally {
      if (this.hasEditSaveBtnTarget) this.editSaveBtnTarget.disabled = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _updateDisplay(name, phone) {
    if (!this.hasDisplayTarget) return;
    if (name) {
      this.displayTarget.innerHTML =
        `<i class="bi bi-person-check-fill text-success me-1"></i>` +
        `<strong>${this._esc(name)}</strong>` +
        (phone
          ? ` <span class="text-muted ms-1"><i class="bi bi-telephone me-1"></i>${this._esc(phone)}</span>`
          : "");
    } else {
      this.displayTarget.innerHTML =
        `<span class="text-muted fst-italic">Sin contacto seleccionado</span>`;
    }
  }

  _highlightChip(selectedBtn) {
    this.element.querySelectorAll("[data-contact-chips] .btn-group button:first-child").forEach((b) => {
      b.classList.remove("btn-primary", "active");
      b.classList.add("btn-outline-secondary");
    });
    selectedBtn.classList.remove("btn-outline-secondary");
    selectedBtn.classList.add("btn-primary", "active");
  }

  _appendChip(contact) {
    const list = this.element.querySelector("[data-contact-chips]");
    if (!list) return;

    const group = document.createElement("div");
    group.className = "btn-group btn-group-sm";
    group.setAttribute("role", "group");

    const selectBtn = document.createElement("button");
    selectBtn.type = "button";
    selectBtn.className = "btn btn-sm btn-outline-secondary";
    selectBtn.dataset.name = contact.name;
    selectBtn.dataset.phone = contact.phone || "";
    selectBtn.dataset.action = "click->contact-selector#select";
    selectBtn.innerHTML =
      `<i class="bi bi-person me-1"></i>${this._esc(contact.name)}` +
      (contact.phone ? ` <span class="opacity-75 ms-1">· ${this._esc(contact.phone)}</span>` : "") +
      (contact.is_primary
        ? ` <span class="badge bg-primary ms-1" style="font-size:.6rem;">Principal</span>`
        : "");

    const editBtn = document.createElement("button");
    editBtn.type = "button";
    editBtn.className = "btn btn-sm btn-outline-secondary";
    editBtn.title = "Editar contacto";
    editBtn.dataset.action = "click->contact-selector#editContact";
    editBtn.dataset.id = contact.id;
    editBtn.dataset.name = contact.name;
    editBtn.dataset.phone = contact.phone || "";
    editBtn.dataset.primary = contact.is_primary ? "true" : "false";
    editBtn.innerHTML = `<i class="bi bi-pencil"></i>`;

    const deleteBtn = document.createElement("button");
    deleteBtn.type = "button";
    deleteBtn.className = "btn btn-sm btn-outline-danger";
    deleteBtn.title = "Eliminar contacto";
    deleteBtn.dataset.action = "click->contact-selector#deleteContact";
    deleteBtn.dataset.deleteId = contact.id;
    deleteBtn.innerHTML = `<i class="bi bi-trash"></i>`;

    group.appendChild(selectBtn);
    group.appendChild(editBtn);
    group.appendChild(deleteBtn);
    list.appendChild(group);
  }

  _updateChip(id, contact) {
    const list = this.element.querySelector("[data-contact-chips]");
    if (!list) return;

    const editBtn = list.querySelector(`[data-id="${id}"]`);
    if (!editBtn) return;

    const group = editBtn.closest(".btn-group");
    const selectBtn = group?.querySelector("[data-action*='select']");

    // Actualizar data en el botón de editar
    editBtn.dataset.name = contact.name;
    editBtn.dataset.phone = contact.phone || "";
    editBtn.dataset.primary = contact.is_primary ? "true" : "false";

    // Actualizar display del botón de selección
    if (selectBtn) {
      selectBtn.dataset.name = contact.name;
      selectBtn.dataset.phone = contact.phone || "";
      selectBtn.innerHTML =
        `<i class="bi bi-person me-1"></i>${this._esc(contact.name)}` +
        (contact.phone ? ` <span class="opacity-75 ms-1">· ${this._esc(contact.phone)}</span>` : "") +
        (contact.is_primary
          ? ` <span class="badge bg-primary ms-1" style="font-size:.6rem;">Principal</span>`
          : "");
    }
  }

  _originalNameForId(id) {
    const btn = this.element.querySelector(`[data-id="${id}"]`);
    return btn ? btn.dataset.name : null;
  }

  _showError(msg) {
    if (!this.hasErrorTarget) return;
    this.errorTarget.textContent = msg;
    this.errorTarget.classList.remove("d-none");
    setTimeout(() => this.errorTarget.classList.add("d-none"), 4000);
  }

  _showEditError(msg) {
    if (!this.hasEditErrorTarget) return;
    this.editErrorTarget.textContent = msg;
    this.editErrorTarget.classList.remove("d-none");
    setTimeout(() => this.editErrorTarget.classList.add("d-none"), 4000);
  }

  _clearAddForm() {
    if (this.hasNameInputTarget) this.nameInputTarget.value = "";
    if (this.hasPhoneInputTarget) this.phoneInputTarget.value = "";
    if (this.hasPrimaryInputTarget) this.primaryInputTarget.checked = false;
    if (this.hasErrorTarget) this.errorTarget.classList.add("d-none");
  }

  _clearEditForm() {
    if (this.hasEditNameInputTarget) this.editNameInputTarget.value = "";
    if (this.hasEditPhoneInputTarget) this.editPhoneInputTarget.value = "";
    if (this.hasEditPrimaryInputTarget) this.editPrimaryInputTarget.checked = false;
    if (this.hasEditErrorTarget) this.editErrorTarget.classList.add("d-none");
  }

  async _request(url, method, body) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const opts = {
      method,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrf,
      },
    };
    if (body !== null) opts.body = JSON.stringify(body);
    const resp = await fetch(url, opts);
    if (!resp.ok) {
      const data = await resp.json().catch(() => ({}));
      throw new Error(data.errors?.join(", ") || "Error en la solicitud");
    }
    if (resp.status === 204) return {};
    return resp.json();
  }

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
