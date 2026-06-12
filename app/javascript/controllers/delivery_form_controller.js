// app/javascript/controllers/delivery_form_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "clientSelect",
    "clientBadge",
    "addClientButton",
    "newClientFields",
    "orderSelect",
    "contactName",
    "contactPhone",
    "contactPicker",
    "contactPickerToggle",
    "contactsList",
    "addContactBtn",
    "newContactForm",
    "newContactName",
    "newContactPhone",
    "newContactPrimary",
    "newContactError",
    "orderBadge",
    "addOrderButton",
    "newOrderFields",
    "addressSelect",
    "addressBadge",
    "newAddressInput",
    "newAddressClientId",
    "newAddressLat",
    "newAddressLng",
    "newAddressPlusCode",
    "newAddressDescription",
    "deliveryDataBadge",
    "productsBadge",
    "itemsContainer",
    "itemTemplate",
    "noItemsRow",
    "rescheduleAlert",
  ];

  static values = {
    addressesUrl: String,
    ordersUrl: String,
  };

  connect() {
    console.log("DeliveryFormController connected");
    this.itemCounter = 0;
    this.validateAllSections();
  }

  // ==================== CLIENTE ====================

  async clientChanged(event) {
    const clientId = event.target.value;

    if (!clientId) {
      this.clearOrderSelect();
      this.clearAddressSelect();
      return;
    }

    await this.loadOrdersForClient(clientId);
    await this.loadAddressesForClient(clientId);

    if (this.hasNewAddressClientIdTarget) {
      this.newAddressClientIdTarget.value = clientId;
    }
  }

  async loadOrdersForClient(clientId) {
    if (!this.hasOrdersUrlValue) return;

    try {
      const response = await fetch(
        `${this.ordersUrlValue}?client_id=${clientId}`,
      );
      const orders = await response.json();
      this.updateOrderSelect(orders);
    } catch (error) {
      console.error("Error loading orders:", error);
    }
  }

  async loadAddressesForClient(clientId) {
    if (!this.hasAddressesUrlValue) return;

    try {
      const response = await fetch(
        `${this.addressesUrlValue}?client_id=${clientId}`,
      );
      const addresses = await response.json();
      this.updateAddressSelect(addresses);
    } catch (error) {
      console.error("Error loading addresses:", error);
    }
  }

  // ← Helper para obtener el searchable-select controller de un <select>
  _getSSController(selectElement) {
    return selectElement?.searchableSelectController || null;
  }

  updateOrderSelect(orders) {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;

    // Actualizar el <select> nativo directamente
    select.innerHTML = '<option value="">Selecciona un pedido</option>';
    orders.forEach((order) => {
      const option = document.createElement("option");
      option.value = order.id;
      option.textContent = order.number;
      select.appendChild(option);
    });

    // Notificar al searchable-select para que re-renderice su dropdown
    const ssController = this._getSSController(select);
    if (ssController) {
      ssController.refreshFromSelect();
    }

    this.validateOrder();
  }

  updateAddressSelect(addresses) {
    if (!this.hasAddressSelectTarget) return;

    const select = this.addressSelectTarget;

    // Actualizar el <select> nativo directamente
    select.innerHTML = '<option value="">Selecciona una dirección</option>';
    addresses.forEach((address) => {
      const option = document.createElement("option");
      option.value = address.id;
      option.textContent = address.address;
      select.appendChild(option);
    });

    // Notificar al searchable-select para que re-renderice su dropdown
    const ssController = this._getSSController(select);
    if (ssController) {
      ssController.refreshFromSelect();
    }

    this.validateAddress();
  }

  clearOrderSelect() {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    select.innerHTML = '<option value="">Selecciona un pedido</option>';

    const ssController = this._getSSController(select);
    if (ssController) {
      ssController.refreshFromSelect();
    }
  }

  clearAddressSelect() {
    if (!this.hasAddressSelectTarget) return;

    const select = this.addressSelectTarget;
    select.innerHTML = '<option value="">Selecciona una dirección</option>';

    const ssController = this._getSSController(select);
    if (ssController) {
      ssController.refreshFromSelect();
    }
  }

  toggleNewClientFields(event) {
    event.preventDefault();

    if (this.hasNewClientFieldsTarget) {
      const isVisible = this.newClientFieldsTarget.style.display !== "none";

      if (isVisible) {
        this.newClientFieldsTarget.style.display = "none";
        this.enableClientSelect();
        this.clearNewClientFields();
      } else {
        this.newClientFieldsTarget.style.display = "block";
        this.disableClientSelect();
      }

      this.validateClient();
    }
  }

  cancelNewClientFields(event) {
    event.preventDefault();

    if (this.hasNewClientFieldsTarget) {
      this.newClientFieldsTarget.style.display = "none";
      this.enableClientSelect();
      this.clearNewClientFields();
      this.validateClient();
    }
  }

  disableClientSelect() {
    if (!this.hasClientSelectTarget) return;

    const select = this.clientSelectTarget;
    const ssController = this._getSSController(select);

    if (ssController) {
      ssController.disable();
    } else {
      select.value = "";
      select.disabled = true;
    }
  }

  enableClientSelect() {
    if (!this.hasClientSelectTarget) return;

    const select = this.clientSelectTarget;
    const ssController = this._getSSController(select);

    if (ssController) {
      ssController.enable();
    } else {
      select.disabled = false;
    }
  }

  clearNewClientFields() {
    if (!this.hasNewClientFieldsTarget) return;

    this.newClientFieldsTarget.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
  }

  validateClient() {
    const hasClient =
      this.hasClientSelectTarget && this.clientSelectTarget.value !== "";
    const hasNewClient =
      this.hasNewClientFieldsTarget &&
      this.newClientFieldsTarget.style.display !== "none" &&
      this.newClientFieldsTarget.querySelector("input[name='client[name]']")
        ?.value;

    this.updateBadge(this.clientBadgeTarget, hasClient || hasNewClient);
  }

  // ==================== PEDIDO ====================

  orderChanged(event) {
    this.validateOrder();
    this._loadOrderContacts(event.target.value);
  }

  _loadOrderContacts(orderId) {
    if (!this.hasContactsListTarget) return;

    if (!orderId) {
      this._renderContactChips([]);
      return;
    }

    fetch(`/orders/${orderId}/order_contacts`, {
      headers: { Accept: "application/json" },
    })
      .then((r) => (r.ok ? r.json() : []))
      .then((contacts) => this._renderContactChips(contacts))
      .catch(() => this._renderContactChips([]));
  }

  _renderContactChips(contacts) {
    if (!this.hasContactsListTarget) return;

    const container = this.contactsListTarget;

    if (!contacts.length) {
      container.innerHTML =
        '<span class="text-muted small fst-italic">Este pedido no tiene contactos guardados.</span>';
      return;
    }

    container.innerHTML = contacts
      .map(
        (c) =>
          `<button type="button"
             class="btn btn-sm ${c.is_primary ? "btn-primary" : "btn-outline-secondary"}"
             data-action="click->delivery-form#pickContact"
             data-name="${this._esc(c.name)}"
             data-phone="${this._esc(c.phone || "")}">
            <i class="bi bi-person me-1"></i>${this._esc(c.name)}
            ${c.phone ? `<span class="ms-1 opacity-75">· ${this._esc(c.phone)}</span>` : ""}
            ${c.is_primary ? '<span class="badge bg-light text-primary ms-1">Principal</span>' : ""}
          </button>`,
      )
      .join("");
  }

  pickContact(event) {
    const btn = event.currentTarget;
    const name = btn.dataset.name;
    const phone = btn.dataset.phone;

    if (this.hasContactNameTarget) this.contactNameTarget.value = name;
    if (this.hasContactPhoneTarget) this.contactPhoneTarget.value = phone;

    // Cerrar el picker
    const picker = this.hasContactPickerTarget ? this.contactPickerTarget : null;
    if (picker) {
      const bsCollapse = bootstrap.Collapse.getInstance(picker);
      if (bsCollapse) bsCollapse.hide();
    }

    this.validateDeliveryData();
  }

  toggleNewContactForm() {
    if (!this.hasNewContactFormTarget) return;
    const form = this.newContactFormTarget;
    const hidden = form.classList.contains("d-none");
    form.classList.toggle("d-none", !hidden);
    if (!hidden) this._clearNewContactForm();
  }

  cancelNewContact() {
    if (this.hasNewContactFormTarget)
      this.newContactFormTarget.classList.add("d-none");
    this._clearNewContactForm();
  }

  async saveNewContact() {
    if (!this.hasNewContactNameTarget) return;

    const name = this.newContactNameTarget.value.trim();
    if (!name) {
      this._showNewContactError("El nombre es obligatorio.");
      return;
    }

    const orderId = this.hasOrderSelectTarget
      ? this.orderSelectTarget.value
      : null;
    if (!orderId) {
      this._showNewContactError("Seleccioná un pedido primero.");
      return;
    }

    const phone = this.hasNewContactPhoneTarget
      ? this.newContactPhoneTarget.value.trim()
      : "";
    const isPrimary = this.hasNewContactPrimaryTarget
      ? this.newContactPrimaryTarget.checked
      : false;

    const csrf = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content");

    try {
      const resp = await fetch(`/orders/${orderId}/order_contacts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf,
        },
        body: JSON.stringify({
          order_contact: { name, phone, is_primary: isPrimary },
        }),
      });

      if (!resp.ok) throw new Error("Error al guardar");

      const saved = await resp.json();

      // Recargar chips y pre-seleccionar el nuevo contacto
      const contacts = await fetch(`/orders/${orderId}/order_contacts`, {
        headers: { Accept: "application/json" },
      }).then((r) => r.json());

      this._renderContactChips(contacts);
      this.cancelNewContact();

      // Auto-seleccionar el recién creado
      if (this.hasContactNameTarget) this.contactNameTarget.value = saved.name;
      if (this.hasContactPhoneTarget)
        this.contactPhoneTarget.value = saved.phone || "";
      this.validateDeliveryData();
    } catch {
      this._showNewContactError("No se pudo guardar el contacto. Intentá de nuevo.");
    }
  }

  _showNewContactError(msg) {
    if (!this.hasNewContactErrorTarget) return;
    const el = this.newContactErrorTarget;
    el.textContent = msg;
    el.classList.remove("d-none");
    setTimeout(() => el.classList.add("d-none"), 4000);
  }

  _clearNewContactForm() {
    if (this.hasNewContactNameTarget) this.newContactNameTarget.value = "";
    if (this.hasNewContactPhoneTarget) this.newContactPhoneTarget.value = "";
    if (this.hasNewContactPrimaryTarget)
      this.newContactPrimaryTarget.checked = false;
    if (this.hasNewContactErrorTarget)
      this.newContactErrorTarget.classList.add("d-none");
  }

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  toggleNewOrderFields(event) {
    event.preventDefault();

    if (this.hasNewOrderFieldsTarget) {
      const isVisible = this.newOrderFieldsTarget.style.display !== "none";

      if (isVisible) {
        this.newOrderFieldsTarget.style.display = "none";
        this.enableOrderSelect();
        this.clearNewOrderFields();
      } else {
        this.newOrderFieldsTarget.style.display = "block";
        this.disableOrderSelect();
      }

      this.validateOrder();
    }
  }

  cancelNewOrderFields(event) {
    event.preventDefault();

    if (this.hasNewOrderFieldsTarget) {
      this.newOrderFieldsTarget.style.display = "none";
      this.enableOrderSelect();
      this.clearNewOrderFields();
      this.validateOrder();
    }
  }

  disableOrderSelect() {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    const ssController = this._getSSController(select);

    if (ssController) {
      ssController.disable();
    } else {
      select.value = "";
      select.disabled = true;
    }
  }

  enableOrderSelect() {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    const ssController = this._getSSController(select);

    if (ssController) {
      ssController.enable();
    } else {
      select.disabled = false;
    }
  }

  clearNewOrderFields() {
    if (!this.hasNewOrderFieldsTarget) return;

    this.newOrderFieldsTarget
      .querySelectorAll("input, select")
      .forEach((input) => {
        input.value = "";
      });
  }

  validateOrder() {
    const hasOrder =
      this.hasOrderSelectTarget && this.orderSelectTarget.value !== "";
    const hasNewOrder =
      this.hasNewOrderFieldsTarget &&
      this.newOrderFieldsTarget.style.display !== "none" &&
      this.newOrderFieldsTarget.querySelector("input[name='order[number]']")
        ?.value;

    this.updateBadge(this.orderBadgeTarget, hasOrder || hasNewOrder);
  }

  // ==================== DIRECCIÓN ====================

  addressChanged(event) {
    this.validateAddress();
  }

  validateAddress() {
    const hasExistingAddress =
      this.hasAddressSelectTarget && this.addressSelectTarget.value !== "";
    const hasNewAddress =
      this.hasNewAddressInputTarget &&
      this.newAddressInputTarget.value.trim() !== "" &&
      this.hasNewAddressLatTarget &&
      this.newAddressLatTarget.value !== "";

    this.updateBadge(
      this.addressBadgeTarget,
      hasExistingAddress || hasNewAddress,
    );
  }

  // ==================== DATOS DE ENTREGA ====================

  checkDateReschedule(event) {
    if (!this.hasRescheduleAlertTarget) return;
    const field = event.target;
    const originalDate = field.dataset.originalDate;
    if (!originalDate) return;
    const changed = field.value !== originalDate;
    this.rescheduleAlertTarget.classList.toggle("d-none", !changed);
  }

  validateDeliveryData() {
    const deliveryDateField = document.querySelector(
      "input[name='delivery[delivery_date]']",
    );
    const contactNameField = document.querySelector(
      "input[name='delivery[contact_name]']",
    );
    const contactPhoneField = document.querySelector(
      "input[name='delivery[contact_phone]']",
    );
    const timePreferenceField = document.querySelector(
      "select[name='delivery[delivery_time_preference]']",
    );

    const hasDeliveryDate = deliveryDateField && deliveryDateField.value !== "";
    const hasContactName =
      contactNameField && contactNameField.value.trim() !== "";
    const hasContactPhone =
      contactPhoneField && contactPhoneField.value.trim() !== "";
    const hasTimePreference =
      timePreferenceField && timePreferenceField.value !== "";

    const isValid =
      hasDeliveryDate && hasContactName && hasContactPhone && hasTimePreference;

    this.updateBadge(this.deliveryDataBadgeTarget, isValid);
  }

  // ==================== PRODUCTOS ====================

  addDeliveryItem(event) {
    event.preventDefault();

    if (!this.hasItemTemplateTarget || !this.hasItemsContainerTarget) return;

    if (this.hasNoItemsRowTarget) {
      this.noItemsRowTarget.style.display = "none";
    }

    const template = this.itemTemplateTarget.cloneNode(true);
    template.classList.remove("delivery-item-template");
    template.style.display = "";

    const timestamp = new Date().getTime() + this.itemCounter++;
    template.innerHTML = template.innerHTML.replace(/NEW_RECORD/g, timestamp);

    this.itemsContainerTarget.appendChild(template);

    this.validateProducts();
  }

  removeDeliveryItem(event) {
    event.preventDefault();

    const row = event.target.closest(".delivery-item-row");
    if (!row) return;

    const destroyField = row.querySelector(".destroy-flag");

    if (destroyField && destroyField.name.includes("[id]")) {
      destroyField.value = "1";
      row.style.display = "none";
    } else {
      row.remove();
    }

    const visibleItems = this.itemsContainerTarget.querySelectorAll(
      ".delivery-item-row:not([style*='display: none'])",
    );
    if (visibleItems.length === 0 && this.hasNoItemsRowTarget) {
      this.noItemsRowTarget.style.display = "";
    }

    this.validateProducts();
  }

  validateProducts() {
    const visibleRows = this.itemsContainerTarget.querySelectorAll(
      ".delivery-item-row:not([style*='display: none'])",
    );

    let hasValidProducts = false;

    visibleRows.forEach((row) => {
      const productInput = row.querySelector("input[name*='[product]']");
      const quantityInput = row.querySelector("input[name*='[quantity]']");
      const quantityDeliveredInput = row.querySelector(
        "input[name*='[quantity_delivered]']",
      );

      if (
        productInput?.value.trim() &&
        quantityInput?.value &&
        parseInt(quantityInput.value) > 0 &&
        quantityDeliveredInput?.value &&
        parseInt(quantityDeliveredInput.value) > 0
      ) {
        hasValidProducts = true;
      }
    });

    this.updateBadge(this.productsBadgeTarget, hasValidProducts);
  }

  // ==================== VALIDACIÓN GENERAL ====================

  validateAllSections() {
    this.validateClient();
    this.validateOrder();
    this.validateAddress();
    this.validateDeliveryData();
    this.validateProducts();
  }

  updateBadge(badge, isValid) {
    if (!badge) return;

    if (isValid) {
      badge.classList.remove("bg-warning");
      badge.classList.add("bg-success");
      badge.textContent = "✓";
    } else {
      badge.classList.remove("bg-success");
      badge.classList.add("bg-warning");
      badge.textContent = "!";
    }
  }
}
