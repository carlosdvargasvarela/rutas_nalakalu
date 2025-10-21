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
    }

    // Utilidad: inserta la opción "Agregar nuevo ..." al inicio si no existe ya
    ensureNewOption(selectEl, label) {
        if (!selectEl) return
        const NEW_VALUE = "__new__"
        const already = Array.from(selectEl.options).some(opt => opt.value === NEW_VALUE)
        if (!already) {
            const opt = document.createElement("option")
            opt.value = NEW_VALUE
            opt.textContent = label
            // Insertar como primera opción
            selectEl.insertBefore(opt, selectEl.firstChild)
        }
    }

    // Utilidad: si el usuario elige "__new__", limpia el select y retorna true
    handleNewSelection(selectEl, onNew) {
        if (!selectEl) return false
        if (selectEl.value === "__new__") {
            // Ejecuta la acción asociada (mostrar formulario)
            onNew?.()
            // Limpia la selección visual
            selectEl.value = ""
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

        // Si elige "Agregar nuevo cliente…"
        const handled = this.handleNewSelection(select, () => this.toggleNewClientFields())
        if (handled) {
            // Al agregar nuevo cliente, limpiamos dependencias
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

        // Si se selecciona un cliente, ocultar y limpiar el bloque de nuevo cliente
        if (clientId && this.hasNewClientFieldsTarget) {
            this.cancelNewClientFields()
        }

        // Actualizar direcciones y pedidos
        if (clientId) {
            // Direcciones
            fetch(`${this.addressesUrlValue}?client_id=${clientId}`)
                .then(response => response.json())
                .then(addresses => {
                    // Reiniciar opciones con placeholder y "Agregar nuevo …"
                    this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
                    this.ensureNewOption(this.addressSelectTarget, "Agregar nueva dirección…")

                    addresses.forEach(address => {
                        this.addressSelectTarget.innerHTML += `<option value="${address.id}">${address.address}</option>`
                    })

                    // Actualizar las direcciones disponibles en el controller de address-autocomplete
                    this.updateAddressControllerData(addresses)
                })
                .catch(error => console.error('Error cargando direcciones:', error))

            // Pedidos
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
            // Limpiar selects si no hay cliente seleccionado
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

        // Habilitar campos de nueva dirección
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
    }

    cancelNewAddressFields() {
        this.newAddressFieldsTarget.style.display = "none"

        // Deshabilitar y limpiar campos
        this.toggleNewAddressFieldsEnabled(false)

        if (this.hasAddAddressButtonTarget) {
            this.addAddressButtonTarget.disabled = false
        }
    }

    addressChanged(event) {
        const select = event.target

        // Si elige "Agregar nueva dirección…"
        const handled = this.handleNewSelection(select, () => this.toggleNewAddressFields())
        if (handled) return

        const addressId = select.value
        console.log("📦 Dirección seleccionada en combo:", addressId)

        // Deshabilitar campos de nueva dirección si se selecciona una existente
        this.toggleNewAddressFieldsEnabled(!addressId)

        // Buscar el controller de address-autocomplete y actualizar la dirección seleccionada
        const addressController = this.application.getControllerForElementAndIdentifier(
            this.newAddressFieldsTarget,
            "address-autocomplete"
        )

        if (addressController) {
            // Actualizar la dirección seleccionada en el controller del mapa
            addressController.updateSelectedAddress(addressId)

            // Si hay una dirección seleccionada, mostrar temporalmente el mapa para que se actualice
            if (addressId) {
                const wasHidden = this.newAddressFieldsTarget.style.display === "none"

                if (wasHidden) {
                    // Mostrar temporalmente para que el mapa se actualice
                    this.newAddressFieldsTarget.style.display = "block"

                    // Inicializar el mapa si no estaba inicializado
                    if (!addressController.map) {
                        addressController.initialize()
                    }

                    // Esperar un momento para que se actualice y luego ocultar
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

        // El client_id siempre debe estar habilitado si hay cliente
        if (this.hasNewAddressClientIdTarget) {
            this.newAddressClientIdTarget.disabled = false
        }
    }

    // Método auxiliar para actualizar los datos del address controller
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

        // Si elige "Agregar nuevo pedido…"
        const handled = this.handleNewSelection(select, () => this.toggleNewOrderFields())
        if (handled) return

        const orderId = select.value
        // Si se selecciona un pedido, ocultar el bloque de nuevo pedido
        if (orderId && this.hasNewOrderFieldsTarget) {
            this.cancelNewOrderFields()
        }
    }

    // === DELIVERY ITEMS MANAGEMENT (opcional, si usas productos dinámicos) ===
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
            // Es un item existente, marcarlo para eliminar
            destroyFlag.value = '1'
            row.style.display = 'none'
        } else {
            // Es un item nuevo, eliminarlo del DOM
            row.remove()
        }
    }
}