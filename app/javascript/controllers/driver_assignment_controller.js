import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["statusBadge", "actions", "noteTextarea", "notesPreview"]
    static values = {
        planId: Number,
        assignmentId: Number,
        lockVersion: Number
    }

    connect() {
        if (!this.hasPlanIdValue) {
            console.error("driver-assignment: falta planIdValue en data-driver-assignment-plan-id-value")
        }
        if (!this.hasAssignmentIdValue) {
            console.error("driver-assignment: falta assignmentIdValue en data-driver-assignment-assignment-id-value")
        }

        // Escuchar mensajes del SW
        if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
            navigator.serviceWorker.addEventListener('message', this.handleSWMessage.bind(this))
        }
    }

    handleSWMessage(event) {
        const { type, actionId, url, status } = event.data

        if (type === 'ACTION_SYNCED') {
            console.log('[Assignment] Action synced:', url)
            // Opcional: refrescar la card específica sin recargar toda la página
            this.refreshAssignment()
        } else if (type === 'ACTION_CONFLICT') {
            console.warn('[Assignment] Action conflict:', url, status)
            alert('Hubo un conflicto al sincronizar. Por favor recarga la página.')
            // Opcional: forzar recarga
            window.location.reload()
        }
    }

    async start(event) {
        event?.preventDefault()
        await this._mutate("start", "Iniciando entrega...")
    }

    async complete(event) {
        event?.preventDefault()
        await this._mutate("complete", "Completando entrega...")
    }

    async markFailed(event) {
        event?.preventDefault()
        const reason = prompt("¿Por qué falló la entrega?")
        if (!reason) return
        await this._mutate("mark_failed", "Marcando como fallida...", { reason })
    }

    openNoteModal(event) {
        event?.preventDefault()
        const modalEl = document.getElementById(`notaModal${this.assignmentIdValue}`)
        if (!modalEl) {
            console.error("No se encontró el modal de nota para assignment", this.assignmentIdValue)
            return
        }
        const modal = bootstrap.Modal.getOrCreateInstance(modalEl)
        modal.show()
    }

    async saveNote(event) {
        event?.preventDefault()
        const text = this.noteTextareaTarget?.value?.trim() || ""
        if (!text) {
            this._showToast("La nota no puede estar vacía", "warning")
            return
        }
        await this._mutate("note", "Guardando nota...", { note: { text } })

        // Limpia textarea y cierra modal explícitamente
        if (this.noteTextareaTarget) this.noteTextareaTarget.value = ""
        const modalEl = document.getElementById(`notaModal${this.assignmentIdValue}`)
        if (modalEl) {
            const modal = bootstrap.Modal.getInstance(modalEl)
            modal?.hide()
        }
    }

    async _mutate(action, loadingMsg, body = {}) {
        this._showToast(loadingMsg, "info")

        const url = `/driver/delivery_plans/${this.planIdValue}/assignments/${this.assignmentIdValue}/${action}.json`
        const headers = this._defaultHeaders()

        try {
            const response = await fetch(url, {
                method: "PATCH",
                headers,
                body: JSON.stringify(body)
            })

            // Si tienes offline-queue, aquí podrías marcar encolado con 202
            const data = await response.json().catch(() => ({}))

            if (response.ok) {
                this._showToast(data.message || "Acción completada", "success")
                this._updateUI(data)
                this._notifyPlanController(data)
            } else if (response.status === 409) {
                this._showToast("Conflicto detectado. Recargando...", "warning")
                setTimeout(() => location.reload(), 1200)
            } else {
                this._showToast(data.error || "Error al procesar la acción", "danger")
            }
        } catch (error) {
            this._showToast("Sin conexión. Acción encolada si está habilitada.", "info")
            this._markPending()
        }
    }

    _updateUI(data) {
        const assignment = data.assignment
        if (!assignment) return

        // 1) Badge de estado
        if (this.hasStatusBadgeTarget) {
            this.statusBadgeTarget.textContent = this._translateStatus(assignment.status)
            this.statusBadgeTarget.className = `badge bg-${this._statusColor(assignment.status)}`
        }

        // 2) Acciones (botones)
        if (this.hasActionsTarget) {
            this.actionsTarget.innerHTML = this._actionsHtmlForStatus(assignment.status)
        }

        // 3) Preview de notas (todas las líneas como lista)
        if (this.hasNotesPreviewTarget) {
            const notes = (assignment.driver_notes || "").toString().trim()
            if (notes.length > 0) {
                const items = notes.split("\n").map(n => `<li>${this._escapeHtml(n)}</li>`).join("")
                this.notesPreviewTarget.innerHTML = `<ul class="mb-0 ps-3">${items}</ul>`
                this.notesPreviewTarget.classList.remove("d-none")
            } else {
                this.notesPreviewTarget.innerHTML = ""
                this.notesPreviewTarget.classList.add("d-none")
            }
        }

        // 4) lock_version
        if (typeof assignment.lock_version === "number") {
            this.lockVersionValue = assignment.lock_version
        }
    }

    _actionsHtmlForStatus(status) {
        const noteBtn = `
          <button type="button" 
                  class="btn btn-outline-primary btn-sm"
                  data-action="click->driver-assignment#openNoteModal">
            <i class="bi bi-sticky me-1"></i>Agregar nota
          </button>
        `
        if (status === "pending") {
            return `
              <button type="button" class="btn btn-success" data-action="click->driver-assignment#start">
                <i class="bi bi-play-circle me-1"></i>Iniciar entrega
              </button>
              <button type="button" class="btn btn-warning" data-action="click->driver-assignment#markFailed">
                <i class="bi bi-exclamation-triangle me-1"></i>Marcar como fallida
              </button>
              ${noteBtn}
            `
        }
        if (status === "in_route") {
            return `
              <button type="button" class="btn btn-primary" data-action="click->driver-assignment#complete">
                <i class="bi bi-check-circle me-1"></i>Completar entrega
              </button>
              <button type="button" class="btn btn-warning" data-action="click->driver-assignment#markFailed">
                <i class="bi bi-exclamation-triangle me-1"></i>Marcar como fallida
              </button>
              ${noteBtn}
            `
        }
        if (status === "completed") {
            return `
              <div class="alert alert-success mb-0 py-2">
                <i class="bi bi-check-circle-fill me-1"></i>
                Entrega completada
              </div>
              ${noteBtn}
            `
        }
        if (status === "cancelled") {
            return `
              <div class="alert alert-danger mb-0 py-2">
                <i class="bi bi-x-circle-fill me-1"></i>
                Entrega cancelada
              </div>
              ${noteBtn}
            `
        }
        return noteBtn
    }

    _markPending() {
        if (this.hasStatusBadgeTarget) {
            this.statusBadgeTarget.className = "badge bg-warning"
            this.statusBadgeTarget.innerHTML = '<i class="bi bi-cloud-arrow-up me-1"></i>Sincronizando...'
        }
    }

    _notifyPlanController(data) {
        document.dispatchEvent(new CustomEvent("driver:assignment:updated", {
            detail: {
                assignmentId: this.assignmentIdValue,
                progress: data.progress
            }
        }))
    }

    _translateStatus(status) {
        const translations = {
            pending: "Pendiente",
            in_route: "En ruta",
            completed: "Completado",
            cancelled: "Cancelado"
        }
        return translations[status] || status
    }

    _statusColor(status) {
        const colors = {
            pending: "secondary",
            in_route: "info",
            completed: "success",
            cancelled: "danger"
        }
        return colors[status] || "secondary"
    }

    _escapeHtml(str) {
        return str.replace(/[&<>"']/g, m => (
            { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]
        ))
    }

    _defaultHeaders() {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-CSRF-Token": token
        }
    }

    _showToast(message, type = "info") {
        document.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type } }))
    }
}