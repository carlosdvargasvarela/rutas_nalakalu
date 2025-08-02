// app/javascript/controllers/delivery_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["clientSelect", "addressSelect", "orderSelect", "newClientFields", "newAddressFields", "newOrderFields"]
    static values = {
        addressesUrl: String,
        ordersUrl: String
    }

    connect() {
        console.log("Delivery form controller connected")
    }

    toggleNewClientFields() {
        const fields = this.newClientFieldsTarget
        fields.style.display = fields.style.display === "none" ? "block" : "none"
    }

    toggleNewAddressFields() {
        const fields = this.newAddressFieldsTarget
        fields.style.display = fields.style.display === "none" ? "block" : "none"
    }

    toggleNewOrderFields() {
        const fields = this.newOrderFieldsTarget
        fields.style.display = fields.style.display === "none" ? "block" : "none"
    }

    addOrderItem(event) {
        event.preventDefault()
        const container = document.getElementById("order-items-fields")
        const template = container.querySelector(".order-item-template")
        const newItem = template.cloneNode(true)

        // Limpiar los valores de los inputs
        newItem.querySelectorAll("input, textarea").forEach(input => {
            input.value = ""
        })

        container.insertBefore(newItem, container.lastElementChild)
    }

    removeOrderItem(event) {
        event.preventDefault()
        const container = document.getElementById("order-items-fields")
        const items = container.querySelectorAll(".order-item-template")

        // Solo remover si hay más de uno
        if (items.length > 1) {
            event.target.closest(".order-item-template").remove()
        }
    }

    addDeliveryItem(event) {
        event.preventDefault()
        const container = document.getElementById("delivery-items-container")
        const template = document.querySelector(".delivery-item-template")
        const newItem = template.cloneNode(true)

        // Mostrar el elemento clonado
        newItem.style.display = "block"
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

    clientChanged(event) {
        const clientId = event.target.value

        // Actualizar direcciones
        fetch(`${this.addressesUrlValue}?client_id=${clientId}`)
            .then(response => response.json())
            .then(addresses => {
                this.addressSelectTarget.innerHTML = '<option value="">Selecciona una dirección</option>'
                addresses.forEach(address => {
                    this.addressSelectTarget.innerHTML += `<option value="${address.id}">${address.address}</option>`
                })
            })

        // Actualizar pedidos
        fetch(`${this.ordersUrlValue}?client_id=${clientId}`)
            .then(response => response.json())
            .then(orders => {
                this.orderSelectTarget.innerHTML = '<option value="">Selecciona un pedido</option>'
                orders.forEach(order => {
                    this.orderSelectTarget.innerHTML += `<option value="${order.id}">${order.number}</option>`
                })
            })
    }
}