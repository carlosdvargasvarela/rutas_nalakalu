import { Controller } from "@hotwired/stimulus"

// Controlador central de cola offline. Expone métodos enqueue() y flush()
// y escucha mensajes del Service Worker para actualizar la UI.
export default class extends Controller {
    static targets = ["status", "badge", "list"]
    static values = {
        syncTag: { type: String, default: "sync-actions" }
    }

    connect() {
        this._bindServiceWorkerMessages()
        this._updateOnlineStatus()

        window.addEventListener("online", this._updateOnlineStatus.bind(this))
        window.addEventListener("offline", this._updateOnlineStatus.bind(this))
    }

    disconnect() {
        window.removeEventListener("online", this._updateOnlineStatus)
        window.removeEventListener("offline", this._updateOnlineStatus)
        navigator.serviceWorker?.removeEventListener("message", this._onSWMessage)
    }

    // Encola una acción de mutación si falla por red o si estamos offline
    // opts = { url, method, body, headers }
    async enqueue(event) {
        event?.preventDefault()

        const button = event?.currentTarget
        button?.setAttribute("disabled", "disabled")

        try {
            const { url, method, body, headers } = this._buildRequestFromElement(button)
            const request = new Request(url, {
                method: method || "PATCH",
                headers: headers || this._defaultHeaders(),
                body: body ? JSON.stringify(body) : null
            })

            // Intentar directo; si falla lo manejará el SW y encolará
            const response = await fetch(request)

            // Si el SW encoló, puede responder 202
            if (response.status === 202) {
                this._showToast("Acción encolada para sincronizar", "info")
                this._markPending(button)
                await this._registerSync()
                return
            }

            if (response.ok) {
                this._showToast("Acción aplicada", "success")
                this._unmarkPending(button)
                await this._refreshIfJSON(response)
            } else {
                // Errores lógicos del server (422/409)
                this._showToast("No se pudo aplicar la acción. Revisión requerida.", "warning")
                this._markConflict(button)
            }
        } catch (e) {
            // Sin conexión o error fetch → el SW encolará si está registrado
            this._showToast("Sin conexión. Acción encolada.", "info")
            this._markPending(button)
            await this._registerSync()
        } finally {
            button?.removeAttribute("disabled")
        }
    }

    // Forzar flush manual de la cola desde el UI (botón “Sincronizar”)
    async flush(event) {
        event?.preventDefault()
        if (!navigator.serviceWorker?.controller) {
            this._showToast("Service Worker no activo todavía", "warning")
            return
        }
        // Disparamos un sync manual invocando el evento en el SW via message
        navigator.serviceWorker.controller.postMessage({ type: "FLUSH_ACTIONS" })
        this._showToast("Sincronizando acciones…", "info")
    }

    // Helpers privados

    _bindServiceWorkerMessages() {
        this._onSWMessage = (event) => {
            const data = event.data || {}
            switch (data.type) {
                case "ACTION_SYNCED":
                    this._showToast("Acción sincronizada", "success")
                    this._refreshIfNeeded()
                    break
                case "ACTION_CONFLICT":
                    this._showToast("Conflicto al sincronizar. Requiere atención.", "warning")
                    break
                case "PING":
                    // noop
                    break
            }
        }

        if (navigator.serviceWorker) {
            navigator.serviceWorker.addEventListener("message", this._onSWMessage)
            // ping
            navigator.serviceWorker.controller?.postMessage({ type: "PING" })
        }
    }

    _updateOnlineStatus() {
        const online = navigator.onLine
        if (this.hasStatusTarget) {
            this.statusTarget.textContent = online ? "En línea" : "Sin conexión"
            this.statusTarget.classList.toggle("text-success", online)
            this.statusTarget.classList.toggle("text-danger", !online)
        }
        if (this.hasBadgeTarget) {
            this.badgeTarget.classList.toggle("bg-success", online)
            this.badgeTarget.classList.toggle("bg-danger", !online)
            this.badgeTarget.textContent = online ? "Online" : "Offline"
        }
    }

    _buildRequestFromElement(el) {
        const url = el?.dataset.url || el?.getAttribute("data-url")
        const method = el?.dataset.method || el?.getAttribute("data-method") || "PATCH"
        let body = null

        // Si tiene data-note-field, leer el valor del textarea
        const noteField = el?.dataset.noteField || el?.getAttribute("data-note-field")
        if (noteField) {
            const textarea = document.querySelector(noteField)
            if (textarea) {
                body = { note: { text: textarea.value } }
            }
        } else {
            const bodyAttr = el?.dataset.body || el?.getAttribute("data-body")
            if (bodyAttr) {
                try {
                    body = JSON.parse(bodyAttr)
                } catch {
                    // Ignorar
                }
            }
        }

        let headers = null
        const headersAttr = el?.dataset.headers || el?.getAttribute("data-headers")
        if (headersAttr) {
            try { headers = JSON.parse(headersAttr) } catch { /* ignore */ }
        }

        const reqId = self.crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`
        headers = Object.assign({}, this._defaultHeaders(), headers, { "X-Request-Id": reqId })

        return { url, method, body, headers }
    }
    
    _defaultHeaders() {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-CSRF-Token": token
        }
    }

    async _registerSync() {
        if ('serviceWorker' in navigator && 'SyncManager' in window) {
            const reg = await navigator.serviceWorker.ready
            await reg.sync.register(this.syncTagValue)
        }
    }

    _markPending(button) {
        if (!button) return
        button.classList.add("btn-warning")
        button.classList.remove("btn-primary", "btn-success")
        const icon = button.querySelector("i")
        if (icon) icon.className = "bi bi-cloud-arrow-up"
    }

    _unmarkPending(button) {
        if (!button) return
        button.classList.remove("btn-warning")
        button.classList.add("btn-success")
        const icon = button.querySelector("i")
        if (icon) icon.className = "bi bi-check2-circle"
    }

    _markConflict(button) {
        if (!button) return
        button.classList.remove("btn-warning")
        button.classList.add("btn-danger")
        const icon = button.querySelector("i")
        if (icon) icon.className = "bi bi-exclamation-octagon"
    }

    async _refreshIfJSON(response) {
        try {
            const data = await response.clone().json()
            // Si quieres forzar refetch de plan.json después de mutaciones:
            // location.reload() puede ser costoso, prefiero emitir evento o usar Turbo.visit
            if (data?.ok) {
                // Notificar a otros componentes
                document.dispatchEvent(new CustomEvent("driver:assignment:updated", { detail: data }))
            }
        } catch {
            // No JSON - ignorar
        }
    }

    _refreshIfNeeded() {
        // Estrategia simple: recargar la página o pedir frames específicos
        // Puedes sustituir por Turbo.visit(location.href, { action: 'replace' })
        // o emitir un evento para que otro controller haga GET /driver/...json
    }

    _showToast(message, type = "info") {
        // Implementación simple usando Bootstrap 5 Toasts si los tienes
        // Aquí dejamos un fallback con alert()
        try {
            const evt = new CustomEvent("toast:show", { detail: { message, type } })
            document.dispatchEvent(evt)
        } catch {
            console.log(`[${type}] ${message}`)
        }
    }
}