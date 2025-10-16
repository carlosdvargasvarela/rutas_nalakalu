import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { id: Number, status: String }

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
                setTimeout(() => location.reload(), 1000)
            } else {
                this._showToast(data.error || "Error al procesar", "danger")
            }
        } catch (error) {
            this._showToast("Sin conexión. Intenta de nuevo.", "warning")
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