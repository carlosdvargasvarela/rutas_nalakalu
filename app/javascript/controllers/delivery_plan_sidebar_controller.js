// app/javascript/controllers/delivery_plan_sidebar_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "summary", "hiddenInputs", "submit"]

    connect() {
        this.selected = this.selected || new Map()
        this.refresh()
        this.syncCheckboxes()
        console.log("DeliveryPlanSidebarController connected")
    }

    syncCheckboxes() {
        const checkboxes = document.querySelectorAll(".delivery-checkbox")
        checkboxes.forEach(cb => {
            cb.checked = this.selected.has(cb.value)
        })
    }

    // Toggle de un checkbox individual
    toggle(event) {
        const cb = event.target
        const id = cb.value
        const label = cb.dataset.label || `Entrega #${id}`

        if (cb.checked) {
            this.selected.set(id, label)
        } else {
            this.selected.delete(id)
        }

        this.refresh()
    }

    // Toggle de "seleccionar todos"
    toggleAll(event) {
        const master = event.target
        const checkboxes = document.querySelectorAll(".delivery-checkbox")

        checkboxes.forEach(cb => {
            cb.checked = master.checked
            const id = cb.value
            const label = cb.dataset.label || `Entrega #${id}`

            if (master.checked) {
                this.selected.set(id, label)
            } else {
                this.selected.delete(id)
            }
        })

        this.refresh()
    }

    // Refrescar sidebar
    refresh() {
        // 1. Limpiar y rellenar lista visual
        this.listTarget.innerHTML = ""
        this.selected.forEach((label, id) => {
            const li = document.createElement("li")
            li.classList.add("list-group-item", "d-flex", "justify-content-between")
            li.innerHTML = `${label} <span class="badge bg-secondary">#${id}</span>`
            this.listTarget.appendChild(li)
        })

        // 2. Actualizar hidden inputs del form
        this.hiddenInputsTarget.innerHTML = ""
        this.selected.forEach((_label, id) => {
            const input = document.createElement("input")
            input.type = "hidden"
            input.name = "delivery_ids[]"
            input.value = id
            this.hiddenInputsTarget.appendChild(input)
        })

        // 3. Actualizar resumen
        this.summaryTarget.textContent = `${this.selected.size} entrega(s) seleccionada(s)`

        // 4. Habilitar/deshabilitar botón submit
        this.submitTarget.disabled = this.selected.size === 0
    }
}