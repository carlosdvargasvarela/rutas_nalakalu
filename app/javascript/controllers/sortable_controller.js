import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
    static targets = ["list"]
    static values = { url: String }

    connect() {
        this.sortable = Sortable.create(this.listTarget, {
            animation: 150,
            ghostClass: "sortable-ghost",
            chosenClass: "sortable-chosen",
            dragClass: "sortable-drag",
            handle: ".drag-handle",
            onEnd: this.onEnd.bind(this)
        })
    }

    disconnect() {
        if (this.sortable) {
            this.sortable.destroy()
        }
    }

    onEnd(event) {
        // Actualizar los números de parada visualmente
        this.updateStopNumbers()

        // Preparar datos para enviar al servidor
        const formData = new FormData()
        const rows = this.listTarget.querySelectorAll("tr[data-assignment-id]")

        rows.forEach((row, index) => {
            const assignmentId = row.dataset.assignmentId
            const stopOrder = index + 1
            formData.append(`stop_orders[${assignmentId}]`, stopOrder)
        })

        // Enviar actualización al servidor
        if (this.urlValue) {
            fetch(this.urlValue, {
                method: "PATCH",
                body: formData,
                headers: {
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
                    "Accept": "application/json"
                }
            })
                .then(response => {
                    if (response.ok) {
                        this.showSuccess()
                    } else {
                        this.showError()
                    }
                })
                .catch(() => {
                    this.showError()
                })
        }
    }

    updateStopNumbers() {
        const rows = this.listTarget.querySelectorAll("tr[data-assignment-id]")
        rows.forEach((row, index) => {
            const stopNumberCell = row.querySelector(".stop-number")
            if (stopNumberCell) {
                stopNumberCell.textContent = index + 1
            }
        })
    }

    showSuccess() {
        // Mostrar mensaje de éxito temporal
        const alert = document.createElement("div")
        alert.className = "alert alert-success alert-dismissible fade show position-fixed"
        alert.style.cssText = "top: 20px; right: 20px; z-index: 1050; min-width: 300px;"
        alert.innerHTML = `
      <i class="bi bi-check-circle me-2"></i>
      Orden actualizado correctamente
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
        document.body.appendChild(alert)

        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove()
            }
        }, 3000)
    }

    showError() {
        // Mostrar mensaje de error temporal
        const alert = document.createElement("div")
        alert.className = "alert alert-danger alert-dismissible fade show position-fixed"
        alert.style.cssText = "top: 20px; right: 20px; z-index: 1050; min-width: 300px;"
        alert.innerHTML = `
      <i class="bi bi-exclamation-triangle me-2"></i>
      Error al actualizar el orden
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
        document.body.appendChild(alert)

        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove()
            }
        }, 5000)
    }
}