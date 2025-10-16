import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["statusBadge", "actions", "startBtn", "completeBtn", "failBtn", "noteTextarea"]
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

    async saveNote(event) {
        event?.preventDefault()
        const text = this.noteTextareaTarget?.value?.trim() || ""
        if (!text) {
            this._showToast("La nota no puede estar vacía", "warning")
            return
        }
        await this._mutate("note", "Guardando nota...", { note: { text } })
        if (this.noteTextareaTarget) this.noteTextareaTarget.value = ""
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

            if (response.status === 202) {
                this._showToast("Acción encolada para sincronizar", "info")
                this._markPending()
                return
            }

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
            this._showToast("Sin conexión. Acción encolada.", "info")
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
            // Re-enlazar eventos a los nuevos botones
            this._bindActionButtons()
        }

        // 3) lock_version
        if (typeof assignment.lock_version === "number") {
            this.lockVersionValue = assignment.lock_version
        }
    }

    _actionsHtmlForStatus(status) {
        // Usamos Bootstrap 5 + Bootstrap Icons
        // Mostramos:
        // - pending: Iniciar + Fallida + Nota
        // - en_route: Completar + Fallida + Nota
        // - completed: alerta de completado + Nota
        // - cancelled: alerta de cancelado + Nota
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
        if (status === "en_route") {
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
        // fallback
        return noteBtn
    }

    _bindActionButtons() {
        // Nada que hacer: Stimulus ata eventos por data-action automáticamente
        // Esta función queda por si necesitas hooks adicionales en el futuro
    }

    openNoteModal() {
        // Abrir el modal existente del partial
        const modalEl = this.element.querySelector('[id^="notaModal"]')
        if (!modalEl) return
        const modal = bootstrap.Modal.getOrCreateInstance(modalEl)
        modal.show()
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
            en_route: "En ruta",
            completed: "Completado",
            cancelled: "Cancelado"
        }
        return translations[status] || status
    }

    _statusColor(status) {
        const colors = {
            pending: "secondary",
            en_route: "info",
            completed: "success",
            cancelled: "danger"
        }
        return colors[status] || "secondary"
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
        const event = new CustomEvent("toast:show", { detail: { message, type } })
        document.dispatchEvent(event)
    }
}