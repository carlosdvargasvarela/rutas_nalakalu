// app/javascript/controllers/delivery_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "clientSelect", "addressSelect", "orderSelect",
        "newClientFields", "newAddressFields", "newOrderFields",
        "addClientButton", "addAddressButton", "addOrderButton"
    ]
    static values = {
        addressesUrl: String,
        ordersUrl: String
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
        const clientId = event.target.value

        // Si se selecciona un cliente, ocultar y limpiar el bloque de nuevo cliente
        if (clientId && this.hasNewClientFieldsTarget) {
            this.cancelNewClientFields()
        }

        // Actualizar direcciones
        if (clientId) {
            fetch(`${this.addressesUrlValue}?client_id=${clientId}`)
                .then(response => response.json())
                .then(addresses => {
                    this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
                    addresses.forEach(address => {
                        this.addressSelectTarget.innerHTML += `<option value="${address.id}">${address.address}</option>`
                    })
                })
                .catch(error => console.error('Error cargando direcciones:', error))

            // Actualizar pedidos
            fetch(`${this.ordersUrlValue}?client_id=${clientId}`)
                .then(response => response.json())
                .then(orders => {
                    this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
                    orders.forEach(order => {
                        this.orderSelectTarget.innerHTML += `<option value="${order.id}">${order.number}</option>`
                    })
                })
                .catch(error => console.error('Error cargando pedidos:', error))
        } else {
            // Limpiar selects si no hay cliente seleccionado
            this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
            this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
        }
    }

    // DIRECCIÓN
    toggleNewAddressFields() {
        this.newAddressFieldsTarget.style.display = "block"
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
        this.newAddressFieldsTarget.querySelectorAll("input, textarea").forEach(input => input.value = "")
        if (this.hasAddAddressButtonTarget) {
            this.addAddressButtonTarget.disabled = false
        }
    }

    addressChanged(event) {
        const addressId = event.target.value
        // Si se selecciona una dirección, ocultar el bloque de nueva dirección
        if (addressId && this.hasNewAddressFieldsTarget) {
            this.cancelNewAddressFields()
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
        const orderId = event.target.value
        // Si se selecciona un pedido, ocultar el bloque de nuevo pedido
        if (orderId && this.hasNewOrderFieldsTarget) {
            this.cancelNewOrderFields()
        }
    }

    // === DELIVERY ITEMS MANAGEMENT (opcional, si usas productos dinámicos) ===
    addDeliveryItem(event) {
        event.preventDefault()
        const container = document.getElementById("delivery-items-container")
        const template = document.querySelector(".delivery-item-template")
        const newItem = template.cloneNode(true)

        // Mostrar el elemento clonado
        newItem.style.display = ""
        newItem.classList.remove("delivery-item-template")

        // Generar un timestamp único para reemplazar NEW_RECORD
        const timestamp = new Date().getTime()
        newItem.innerHTML = newItem.innerHTML.replace(/NEW_RECORD/g, timestamp)

        // Limpiar valores
        newItem.querySelectorAll("input, textarea, select").forEach(input => {
            if (input.type !== "checkbox") {
                input.value = input.type === "number" ? "1" : ""
            } else {
                input.checked = false
            }
        })

        const addButtonRow = container.querySelector(".row:last-child")
        container.insertBefore(newItem, addButtonRow)
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