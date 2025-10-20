// app/javascript/controllers/driver_assignment_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["statusBadge", "actions", "noteTextarea", "notesPreview"]
    static values = {
        planId: Number,
        assignmentId: Number,
        lockVersion: Number
    }

    connect() {
        if (!this.hasPlanIdValue || !this.hasAssignmentIdValue) {
            console.error("driver-assignment: faltan planIdValue o assignmentIdValue")
        }

        // Escuchar mensajes del service worker por si hay sync offline
        if ("serviceWorker" in navigator && navigator.serviceWorker.controller) {
            navigator.serviceWorker.addEventListener("message", this.handleSWMessage.bind(this))
        }
    }

    handleSWMessage(event) {
        const { type, url } = event.data || {}
        if (type === "ACTION_SYNCED") {
            console.log("[Assignment] Acción sincronizada:", url)
            this.refreshAssignment()
        }
    }

    async start(e) {
        e?.preventDefault()
        await this._mutate("start", "Iniciando entrega...")
    }

    async complete(e) {
        e?.preventDefault()
        await this._mutate("complete", "Completando entrega...")
    }

    async markFailed(e) {
        e?.preventDefault()
        const reason = prompt("Motivo del fallo:", "Cliente ausente o dirección incorrecta")
        if (!reason) return
        await this._mutate("mark_failed", "Marcando como fallida...", { reason })
    }

    openNoteModal(e) {
        e?.preventDefault()
        const modalEl = document.getElementById(`notaModal${this.assignmentIdValue}`)
        if (!modalEl) return
        const modal = bootstrap.Modal.getOrCreateInstance(modalEl)
        modal.show()
    }

    async saveNote(e) {
        e?.preventDefault()
        const text = this.noteTextareaTarget?.value?.trim() || ""
        if (!text) {
            this._showToast("La nota no puede estar vacía", "warning")
            return
        }
        await this._mutate("note", "Guardando nota...", { note: { text } })

        this.noteTextareaTarget.value = ""
        const modalEl = document.getElementById(`notaModal${this.assignmentIdValue}`)
        if (modalEl) bootstrap.Modal.getInstance(modalEl)?.hide()
    }

    async _mutate(action, loadingMsg, body = {}) {
        this._showToast(loadingMsg, "info")
        const url = `/driver/delivery_plans/${this.planIdValue}/assignments/${this.assignmentIdValue}/${action}.json`

        try {
            const response = await fetch(url, {
                method: "PATCH",
                headers: this._defaultHeaders(),
                body: JSON.stringify(body)
            })

            const data = await response.json().catch(() => ({}))

            if (response.ok) {
                this._showToast(data.message || "Acción completada", "success")
                this._updateUI(data)

                // 🔁 notificar al resto del sistema (mapas, dashboard, etc.)
                document.dispatchEvent(
                    new CustomEvent("assignment:updated", {
                        detail: { assignment: data.assignment, progress: data.progress },
                        bubbles: true
                    })
                )
            } else if (response.status === 409) {
                this._showToast("Conflicto detectado. Recargando...", "warning")
                setTimeout(() => location.reload(), 1200)
            } else {
                this._showToast(data.error || "Error al procesar la acción", "danger")
            }
        } catch (err) {
            console.error("Error:", err)
            this._showToast("Sin conexión o error inesperado", "info")
            this._markPending()
        }
    }

    _updateUI(data) {
        const assignment = data.assignment
        if (!assignment) return

        // Estado
        if (this.hasStatusBadgeTarget) {
            this.statusBadgeTarget.textContent = this._translateStatus(assignment.status)
            this.statusBadgeTarget.className = `badge bg-${this._statusColor(assignment.status)}`
        }

        // Acciones disponibles
        if (this.hasActionsTarget) {
            this.actionsTarget.innerHTML = this._actionsHtmlForStatus(assignment.status)
        }

        // Notas
        if (this.hasNotesPreviewTarget) {
            const notes = (assignment.driver_notes || "").trim()
            if (notes) {
                const items = notes
                    .split("\n")
                    .map(n => `<li>${this._escapeHtml(n)}</li>`)
                    .join("")
                this.notesPreviewTarget.innerHTML = `<ul class="mb-0 ps-3">${items}</ul>`
                this.notesPreviewTarget.classList.remove("d-none")
            } else {
                this.notesPreviewTarget.innerHTML = ""
                this.notesPreviewTarget.classList.add("d-none")
            }
        }

        // Lock version
        if (typeof assignment.lock_version === "number") {
            this.lockVersionValue = assignment.lock_version
        }
    }

    _actionsHtmlForStatus(status) {
        const noteBtn = `
      <button type="button" class="btn btn-outline-primary btn-sm" data-action="click->driver-assignment#openNoteModal">
        <i class="bi bi-sticky me-1"></i>Agregar nota
      </button>
    `
        if (status === "pending") {
            return `
        <button class="btn btn-success" data-action="click->driver-assignment#start">
          <i class="bi bi-play-circle me-1"></i>Iniciar
        </button>
        <button class="btn btn-warning" data-action="click->driver-assignment#markFailed">
          <i class="bi bi-exclamation-triangle me-1"></i>Fallida
        </button>
        ${noteBtn}
      `
        }
        if (status === "in_route") {
            return `
        <button class="btn btn-primary" data-action="click->driver-assignment#complete">
          <i class="bi bi-check-circle me-1"></i>Completar
        </button>
        <button class="btn btn-warning" data-action="click->driver-assignment#markFailed">
          <i class="bi bi-exclamation-triangle me-1"></i>Fallida
        </button>
        ${noteBtn}
      `
        }
        if (status === "completed") {
            return `<div class="alert alert-success mb-0 py-2"><i class="bi bi-check-circle-fill me-1"></i>Completada</div>${noteBtn}`
        }
        if (status === "cancelled") {
            return `<div class="alert alert-danger mb-0 py-2"><i class="bi bi-x-circle-fill me-1"></i>Fallida</div>${noteBtn}`
        }
        return noteBtn
    }

    _markPending() {
        if (this.hasStatusBadgeTarget) {
            this.statusBadgeTarget.className = "badge bg-warning"
            this.statusBadgeTarget.innerHTML = `<i class="bi bi-cloud-arrow-up me-1"></i>Sincronizando...`
        }
    }

    _translateStatus(status) {
        return {
            pending: "Pendiente",
            in_route: "En ruta",
            completed: "Completado",
            cancelled: "Fallida"
        }[status] || status
    }

    _statusColor(status) {
        return {
            pending: "secondary",
            in_route: "info",
            completed: "success",
            cancelled: "danger"
        }[status] || "secondary"
    }

    _escapeHtml(str) {
        return str.replace(/[&<>"']/g, m => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]))
    }

    _defaultHeaders() {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        return {
            "Content-Type": "application/json",
            Accept: "application/json",
            "X-CSRF-Token": token
        }
    }

    _showToast(message, type = "info") {
        document.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type } }))
    }
}