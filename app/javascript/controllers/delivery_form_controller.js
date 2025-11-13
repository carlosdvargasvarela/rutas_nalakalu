import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "clientSelect",
    "clientBadge",
    "addClientButton",
    "newClientFields",
    "orderSelect",
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

    // Cargar pedidos del cliente
    await this.loadOrdersForClient(clientId);

    // Cargar direcciones del cliente
    await this.loadAddressesForClient(clientId);

    // Actualizar client_id en el campo oculto de nueva dirección
    if (this.hasNewAddressClientIdTarget) {
      this.newAddressClientIdTarget.value = clientId;
    }
  }

  async loadOrdersForClient(clientId) {
    if (!this.hasOrdersUrlValue) return;

    try {
      const response = await fetch(
        `${this.ordersUrlValue}?client_id=${clientId}`
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
        `${this.addressesUrlValue}?client_id=${clientId}`
      );
      const addresses = await response.json();

      this.updateAddressSelect(addresses);
    } catch (error) {
      console.error("Error loading addresses:", error);
    }
  }

  updateOrderSelect(orders) {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clearOptions();
      tomSelect.addOption({ value: "", text: "Selecciona un pedido" });

      orders.forEach((order) => {
        tomSelect.addOption({
          value: order.id,
          text: `${order.number} - ${order.seller_name || "Sin vendedor"}`,
        });
      });

      tomSelect.refreshOptions(false);
    } else {
      // Fallback sin TomSelect
      select.innerHTML = '<option value="">Selecciona un pedido</option>';
      orders.forEach((order) => {
        const option = document.createElement("option");
        option.value = order.id;
        option.textContent = `${order.number} - ${
          order.seller_name || "Sin vendedor"
        }`;
        select.appendChild(option);
      });
    }
  }

  updateAddressSelect(addresses) {
    if (!this.hasAddressSelectTarget) return;

    const select = this.addressSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clearOptions();
      tomSelect.addOption({ value: "", text: "Selecciona una dirección" });

      addresses.forEach((address) => {
        tomSelect.addOption({
          value: address.id,
          text: address.address,
        });
      });

      tomSelect.refreshOptions(false);
    } else {
      // Fallback sin TomSelect
      select.innerHTML = '<option value="">Selecciona una dirección</option>';
      addresses.forEach((address) => {
        const option = document.createElement("option");
        option.value = address.id;
        option.textContent = address.address;
        select.appendChild(option);
      });
    }
  }

  clearOrderSelect() {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clear();
      tomSelect.clearOptions();
    } else {
      select.innerHTML = '<option value="">Selecciona un pedido</option>';
    }
  }

  clearAddressSelect() {
    if (!this.hasAddressSelectTarget) return;

    const select = this.addressSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clear();
      tomSelect.clearOptions();
    } else {
      select.innerHTML = '<option value="">Selecciona una dirección</option>';
    }
  }

  toggleNewClientFields(event) {
    event.preventDefault();

    if (this.hasNewClientFieldsTarget) {
      const isVisible = this.newClientFieldsTarget.style.display !== "none";

      if (isVisible) {
        // Ocultar formulario de nuevo cliente
        this.newClientFieldsTarget.style.display = "none";
        this.enableClientSelect();
        this.clearNewClientFields();
      } else {
        // Mostrar formulario de nuevo cliente
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
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clear();
      tomSelect.disable();
    } else {
      select.value = "";
      select.disabled = true;
    }
  }

  enableClientSelect() {
    if (!this.hasClientSelectTarget) return;

    const select = this.clientSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.enable();
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
    // Simplemente validar, no hacer llamadas adicionales
    this.validateOrder();
  }

  toggleNewOrderFields(event) {
    event.preventDefault();

    if (this.hasNewOrderFieldsTarget) {
      const isVisible = this.newOrderFieldsTarget.style.display !== "none";

      if (isVisible) {
        // Ocultar formulario de nuevo pedido
        this.newOrderFieldsTarget.style.display = "none";
        this.enableOrderSelect();
        this.clearNewOrderFields();
      } else {
        // Mostrar formulario de nuevo pedido
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
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.clear();
      tomSelect.disable();
    } else {
      select.value = "";
      select.disabled = true;
    }
  }

  enableOrderSelect() {
    if (!this.hasOrderSelectTarget) return;

    const select = this.orderSelectTarget;
    const tomSelect = select.tomselect;

    if (tomSelect) {
      tomSelect.enable();
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
    // Solo validar, el mapa se actualiza con address-selector controller
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
      hasExistingAddress || hasNewAddress
    );
  }

  // ==================== DATOS DE ENTREGA ====================

  validateDeliveryData() {
    const deliveryDateField = document.querySelector(
      "input[name='delivery[delivery_date]']"
    );
    const contactNameField = document.querySelector(
      "input[name='delivery[contact_name]']"
    );
    const contactPhoneField = document.querySelector(
      "input[name='delivery[contact_phone]']"
    );
    const timePreferenceField = document.querySelector(
      "select[name='delivery[delivery_time_preference]']"
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

    // Ocultar mensaje "no hay productos"
    if (this.hasNoItemsRowTarget) {
      this.noItemsRowTarget.style.display = "none";
    }

    const template = this.itemTemplateTarget.cloneNode(true);
    template.classList.remove("delivery-item-template");
    template.style.display = "";

    // Reemplazar NEW_RECORD con un timestamp único
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
      // Item existente: marcar para destruir
      destroyField.value = "1";
      row.style.display = "none";
    } else {
      // Item nuevo: eliminar del DOM
      row.remove();
    }

    // Mostrar mensaje si no quedan items visibles
    const visibleItems = this.itemsContainerTarget.querySelectorAll(
      ".delivery-item-row:not([style*='display: none'])"
    );
    if (visibleItems.length === 0 && this.hasNoItemsRowTarget) {
      this.noItemsRowTarget.style.display = "";
    }

    this.validateProducts();
  }

  validateProducts() {
    const visibleRows = this.itemsContainerTarget.querySelectorAll(
      ".delivery-item-row:not([style*='display: none'])"
    );

    let hasValidProducts = false;

    visibleRows.forEach((row) => {
      const productInput = row.querySelector("input[name*='[product]']");
      const quantityInput = row.querySelector("input[name*='[quantity]']");
      const quantityDeliveredInput = row.querySelector(
        "input[name*='[quantity_delivered]']"
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
