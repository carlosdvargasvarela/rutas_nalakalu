// app/javascript/controllers/delivery_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "clientSelect", "addressSelect", "orderSelect",
        "newClientFields", "newAddressFields", "newOrderFields",
        "addClientButton", "addAddressButton", "addOrderButton",
        "newAddressInput", "newAddressClientId", "newAddressLat",
        "newAddressLng", "newAddressPlusCode", "newAddressDescription"
    ]

    static values = {
        addressesUrl: String,
        ordersUrl: String
    }

    connect() {
        // Asegurar que todos los selects tengan la opción "Agregar nuevo ..."
        if (this.hasAddressSelectTarget) {
            this.ensureNewOption(this.addressSelectTarget, "Agregar nueva dirección…")
        }
        if (this.hasOrderSelectTarget) {
            this.ensureNewOption(this.orderSelectTarget, "Agregar nuevo pedido…")
        }

        // Pre-submit defensivo: limpiar "__new__" si se quedó en el select
        this.element.addEventListener("submit", (e) => {
            if (this.hasAddressSelectTarget) {
                if (this.addressSelectTarget.value === "__new__") {
                    this.addressSelectTarget.value = ""
                }
            }
        })
    }

    ensureNewOption(selectEl, label) {
        if (!selectEl) return
        const NEW_VALUE = "__new__"
        const already = Array.from(selectEl.options).some(opt => opt.value === NEW_VALUE)
        if (!already) {
            const opt = document.createElement("option")
            opt.value = NEW_VALUE
            opt.textContent = label
            selectEl.insertBefore(opt, selectEl.firstChild)
        }
    }

    handleNewSelection(selectEl, onNew) {
        if (!selectEl) return false
        if (selectEl.value === "__new__") {
            onNew?.()
            // Limpiar selección y notificar cambio para que Turbo/validaciones se actualicen
            selectEl.value = ""
            selectEl.dispatchEvent(new Event("change"))
            return true
        }
        return false
    }

    // CLIENTE
    toggleNewClientFields() {
        this.newClientFieldsTarget.style.display = "block"
        if (this.hasAddClientButtonTarget) {
            this.addClientButtonTarget.disabled = true
        }
    }

    cancelNewClientFields() {
        this.newClientFieldsTarget.style.display = "none"
        this.newClientFieldsTarget.querySelectorAll("input").forEach(input => input.value = "")
        if (this.hasAddClientButtonTarget) {
            this.addClientButtonTarget.disabled = false
        }
    }

    clientChanged(event) {
        const select = event.target

        const handled = this.handleNewSelection(select, () => this.toggleNewClientFields())
        if (handled) {
            if (this.hasAddressSelectTarget) {
                this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
                this.ensureNewOption(this.addressSelectTarget, "Agregar nueva dirección…")
            }
            if (this.hasOrderSelectTarget) {
                this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
                this.ensureNewOption(this.orderSelectTarget, "Agregar nuevo pedido…")
            }
            return
        }

        const clientId = select.value

        if (clientId && this.hasNewClientFieldsTarget) {
            this.cancelNewClientFields()
        }

        if (clientId) {
            fetch(`${this.addressesUrlValue}?client_id=${clientId}`)
                .then(response => response.json())
                .then(addresses => {
                    this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
                    this.ensureNewOption(this.addressSelectTarget, "Agregar nueva dirección…")

                    addresses.forEach(address => {
                        this.addressSelectTarget.innerHTML += `<option value="${address.id}">${address.address}</option>`
                    })
                    this.updateAddressControllerData(addresses)
                })
                .catch(error => console.error('Error cargando direcciones:', error))

            fetch(`${this.ordersUrlValue}?client_id=${clientId}`)
                .then(response => response.json())
                .then(orders => {
                    this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
                    this.ensureNewOption(this.orderSelectTarget, "Agregar nuevo pedido…")

                    orders.forEach(order => {
                        this.orderSelectTarget.innerHTML += `<option value="${order.id}">${order.number}</option>`
                    })
                })
                .catch(error => console.error('Error cargando pedidos:', error))
        } else {
            this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
            this.ensureNewOption(this.addressSelectTarget, "Agregar nueva dirección…")

            this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
            this.ensureNewOption(this.orderSelectTarget, "Agregar nuevo pedido…")
        }

        const wizardController = this.application.getControllerForElementAndIdentifier(
            this.element, "delivery-wizard"
        )
        if (wizardController) {
            wizardController.refreshIcons()
        }
    }

    // DIRECCIÓN
    toggleNewAddressFields() {
        this.newAddressFieldsTarget.style.display = "block"
        this.toggleNewAddressFieldsEnabled(true)

        const addressController = this.application.getControllerForElementAndIdentifier(
            this.newAddressFieldsTarget,
            "address-autocomplete"
        )
        if (addressController) {
            addressController.initialize()
        }
        if (this.hasAddAddressButtonTarget) {
            this.addAddressButtonTarget.disabled = true
        }

        // Asegurar que el select no quede en "__new__"
        if (this.hasAddressSelectTarget) {
            this.addressSelectTarget.value = ""
            this.addressSelectTarget.dispatchEvent(new Event("change"))
        }
    }

    cancelNewAddressFields() {
        this.newAddressFieldsTarget.style.display = "none"
        this.toggleNewAddressFieldsEnabled(false)

        if (this.hasAddAddressButtonTarget) {
            this.addAddressButtonTarget.disabled = false
        }
    }

    addressChanged(event) {
        const select = event.target

        const handled = this.handleNewSelection(select, () => this.toggleNewAddressFields())
        if (handled) return

        const addressId = select.value
        this.toggleNewAddressFieldsEnabled(!addressId)

        const addressController = this.application.getControllerForElementAndIdentifier(
            this.newAddressFieldsTarget,
            "address-autocomplete"
        )

        if (addressController) {
            addressController.updateSelectedAddress(addressId)

            if (addressId) {
                const wasHidden = this.newAddressFieldsTarget.style.display === "none"
                if (wasHidden) {
                    this.newAddressFieldsTarget.style.display = "block"
                    if (!addressController.map) {
                        addressController.initialize()
                    }
                    setTimeout(() => {
                        this.newAddressFieldsTarget.style.display = "none"
                    }, 100)
                }
            }
        }
    }

    toggleNewAddressFieldsEnabled(enabled) {
        if (!this.hasNewAddressInputTarget) return

        const fields = [
            this.newAddressInputTarget,
            this.newAddressLatTarget,
            this.newAddressLngTarget,
            this.newAddressPlusCodeTarget,
            this.newAddressDescriptionTarget
        ]

        fields.forEach(field => {
            if (field) {
                field.disabled = !enabled
                if (!enabled) field.value = ""
            }
        })

        if (this.hasNewAddressClientIdTarget) {
            this.newAddressClientIdTarget.disabled = false
        }
    }

    updateAddressControllerData(addresses) {
        const addressController = this.application.getControllerForElementAndIdentifier(
            this.newAddressFieldsTarget,
            "address-autocomplete"
        )

        if (addressController) {
            addressController.addressesValue = addresses
        }
    }

    // PEDIDO
    toggleNewOrderFields() {
        this.newOrderFieldsTarget.style.display = "block"
        if (this.hasAddOrderButtonTarget) {
            this.addOrderButtonTarget.disabled = true
        }
    }

    cancelNewOrderFields() {
        this.newOrderFieldsTarget.style.display = "none"
        this.newOrderFieldsTarget.querySelectorAll("input, textarea, select").forEach(input => input.value = "")
        if (this.hasAddOrderButtonTarget) {
            this.addOrderButtonTarget.disabled = false
        }
    }

    orderChanged(event) {
        const select = event.target
        const handled = this.handleNewSelection(select, () => this.toggleNewOrderFields())
        if (handled) return

        const orderId = select.value
        if (orderId && this.hasNewOrderFieldsTarget) {
            this.cancelNewOrderFields()
        }
    }

    addDeliveryItem(event) {
        event.preventDefault();
        const container = document.getElementById("delivery-items-container");
        const template = document.querySelector(".delivery-item-template");
        const newItem = template.cloneNode(true);

        newItem.style.display = "";
        newItem.classList.remove("delivery-item-template");

        const timestamp = new Date().getTime();
        newItem.innerHTML = newItem.innerHTML.replace(/NEW_RECORD/g, timestamp);

        container.appendChild(newItem);
    }

    removeDeliveryItem(event) {
        event.preventDefault()
        const row = event.target.closest('.delivery-item-row')
        const destroyFlag = row.querySelector('.destroy-flag')

        if (destroyFlag) {
            destroyFlag.value = '1'
            row.style.display = 'none'
        } else {
            row.remove()
        }
    }
}