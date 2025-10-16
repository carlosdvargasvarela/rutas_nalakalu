import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { id: Number, status: String }
    static targets = ["progressBar", "completedCount", "enRouteCount", "pendingCount", "totalCount"]

    connect() {
        // Escuchar el evento de actualización de asignaciones
        this._onAssignmentUpdatedBound = this._onAssignmentUpdated.bind(this)
        document.addEventListener("driver:assignment:updated", this._onAssignmentUpdatedBound)
    }

    disconnect() {
        if (this._onAssignmentUpdatedBound) {
            document.removeEventListener("driver:assignment:updated", this._onAssignmentUpdatedBound)
        }
    }

    async startPlan(event) {
        event.preventDefault()
        if (!confirm("¿Iniciar la ruta?")) return
        await this._mutatePlan("start", "Iniciando ruta...")
    }

    async finishPlan(event) {
        event.preventDefault()
        if (!confirm("¿Finalizar la ruta?")) return
        await this._mutatePlan("finish", "Finalizando ruta...")
    }

    async abortPlan(event) {
        event.preventDefault()
        if (!confirm("¿Abortar la ruta? Esta acción no se puede deshacer.")) return
        await this._mutatePlan("abort", "Abortando ruta...")
    }

    async _mutatePlan(action, loadingMsg) {
        this._showToast(loadingMsg, "info")
        const url = `/driver/delivery_plans/${this.idValue}/${action}.json`
        const headers = this._defaultHeaders()

        try {
            const response = await fetch(url, { method: "PATCH", headers })
            const data = await response.json()
            if (response.ok) {
                this._showToast(data.message || "Acción completada", "success")
                this.statusValue = data.status
                // Emitir evento para que el tracker reaccione
                document.dispatchEvent(new CustomEvent("driver:plan:status-changed", {
                    detail: { status: data.status }
                }))
                setTimeout(() => location.reload(), 1000)
            } else {
                this._showToast(data.error || "Error al procesar", "danger")
            }
        } catch (error) {
            this._showToast("Sin conexión. Intenta de nuevo.", "warning")
        }
    }

    _onAssignmentUpdated(event) {
        const { progress } = event.detail
        if (progress) {
            this._updateProgressBar(progress)
        }
    }

    _updateProgressBar(progress) {
        const { completed, en_route, pending, total } = progress

        // Actualizar los contadores si existen los targets
        if (this.hasCompletedCountTarget) {
            this.completedCountTarget.textContent = completed
        }
        if (this.hasEnRouteCountTarget) {
            this.enRouteCountTarget.textContent = en_route
        }
        if (this.hasPendingCountTarget) {
            this.pendingCountTarget.textContent = pending
        }
        if (this.hasTotalCountTarget) {
            this.totalCountTarget.textContent = total
        }

        // Actualizar la barra de progreso si existe el target
        if (this.hasProgressBarTarget && total > 0) {
            const completedPercentage = Math.round((completed / total) * 100)
            this.progressBarTarget.style.width = `${completedPercentage}%`
            this.progressBarTarget.setAttribute('aria-valuenow', completedPercentage)
            this.progressBarTarget.textContent = `${completedPercentage}%`

            // Cambiar color según progreso
            this.progressBarTarget.className = 'progress-bar'
            if (completedPercentage === 100) {
                this.progressBarTarget.classList.add('bg-success')
            } else if (completedPercentage >= 50) {
                this.progressBarTarget.classList.add('bg-info')
            } else {
                this.progressBarTarget.classList.add('bg-primary')
            }
        } else if (this.hasProgressBarTarget) {
            this.progressBarTarget.style.width = '0%'
            this.progressBarTarget.setAttribute('aria-valuenow', 0)
            this.progressBarTarget.textContent = '0%'
        }
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