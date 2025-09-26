// app/javascript/controllers/delivery_plan_sidebar_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "summary", "hiddenInputs", "submit"]

    connect() {
        this.selected = new Map()
        this.refresh()
        console.log("DeliveryPlanSidebarController connected")
    }

    toggle(event) {
        const checkbox = event.target
        const id = checkbox.value
        const label = checkbox.dataset.label || `Entrega #${id}`

        if (checkbox.checked) {
            this.selected.set(id, label)
        } else {
            this.selected.delete(id)
        }

        this.refresh()
    }

    toggleAll(event) {
        const master = event.target
        const checkboxes = document.querySelectorAll('input[name="delivery_ids[]"]')

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

    refresh() {
        // 1. Actualizar lista visual
        this.listTarget.innerHTML = ""
        this.selected.forEach((label, id) => {
            const li = document.createElement("li")
            li.classList.add("list-group-item", "d-flex", "justify-content-between")
            li.innerHTML = `${label} <span class="badge bg-secondary">#${id}</span>`
            this.listTarget.appendChild(li)
        })

        // 2. Actualizar hidden inputs
        this.hiddenInputsTarget.innerHTML = ""
        this.selected.forEach((_label, id) => {
            const input = document.createElement("input")
            input.type = "hidden"
            input.name = "delivery_ids[]"
            input.value = id
            this.hiddenInputsTarget.appendChild(input)
        })

        // 3. Summary
        this.summaryTarget.textContent = `${this.selected.size} entrega(s) seleccionada(s)`

        // 4. Habilitar/deshabilitar submit
        this.submitTarget.disabled = this.selected.size === 0
    }
}