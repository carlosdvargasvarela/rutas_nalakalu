// app/javascript/controllers/driver_tracker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        deliveryPlanId: Number,
        planStatus: String, // 👈 NUEVO: recibir el estado del plan
        updateInterval: { type: Number, default: 30000 },
        batchSize: { type: Number, default: 10 }
    }

    connect() {
        console.log("🚚 Driver Tracker conectado")
        this.positionQueue = []
        this.watchId = null
        this.syncInterval = null

        // 🔒 No iniciar tracking si el plan ya está completado o abortado
        if (this.planStatusValue === "completed" || this.planStatusValue === "aborted") {
            console.log("⏹ Plan finalizado, no se inicia tracking")
            this.updateStatus("tracking", "Tracking: OFF (Plan finalizado)", "secondary")
            return
        }

        if (this.hasDeliveryPlanIdValue) {
            this.startTracking()
        }

        // 🔁 Escuchar evento global cuando se complete el plan
        document.addEventListener("delivery_plan:completed", this.handlePlanCompleted.bind(this))
    }

    disconnect() {
        console.log("🛑 Driver Tracker desconectado")
        document.removeEventListener("delivery_plan:completed", this.handlePlanCompleted.bind(this))
        this.stopTracking()
    }

    handlePlanCompleted(event) {
        if (event.detail?.planId === this.deliveryPlanIdValue) {
            console.log("✅ Plan completado, deteniendo tracking")
            this.stopTracking()
        }
    }

    startTracking() {
        if (!navigator.geolocation) {
            console.error("❌ Geolocalización no disponible")
            this.showError("Tu dispositivo no soporta GPS")
            return
        }

        const options = {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 0
        }

        this.watchId = navigator.geolocation.watchPosition(
            (position) => this.handlePosition(position),
            (error) => this.handleError(error),
            options
        )

        this.syncInterval = setInterval(() => {
            this.syncPositions()
        }, this.updateIntervalValue)

        this.updateStatus("tracking", "Tracking: ON", "success")
        console.log("✅ Tracking iniciado")
    }

    stopTracking() {
        if (this.watchId) {
            navigator.geolocation.clearWatch(this.watchId)
            this.watchId = null
        }

        if (this.syncInterval) {
            clearInterval(this.syncInterval)
            this.syncInterval = null
        }

        // Enviar posiciones pendientes antes de detener
        if (this.positionQueue.length > 0) {
            this.syncPositions()
        }

        this.updateStatus("tracking", "Tracking: OFF", "secondary")
        console.log("🛑 Tracking detenido")
    }

    handlePosition(position) {
        // 🔒 Verificar estado antes de procesar posición
        if (this.planStatusValue === "completed" || this.planStatusValue === "aborted") {
            console.log("⏹ Plan finalizado durante tracking, deteniendo...")
            this.stopTracking()
            return
        }

        const { latitude, longitude, accuracy, speed, heading } = position.coords
        const timestamp = new Date(position.timestamp).toISOString()

        console.log(`📍 Nueva posición: ${latitude}, ${longitude} (±${accuracy}m)`)

        this.positionQueue.push({
            lat: latitude,
            lng: longitude,
            accuracy: accuracy,
            speed: speed || 0,
            heading: heading || 0,
            at: timestamp
        })

        this.updateStatus("gps", "GPS Activo", "success")
        this.updateLastPosition(latitude, longitude, timestamp)

        if (this.positionQueue.length >= this.batchSizeValue) {
            this.syncPositions()
        }
    }

    handleError(error) {
        console.error("❌ Error GPS:", error.message)

        let message = "Error de GPS"
        switch (error.code) {
            case error.PERMISSION_DENIED:
                message = "Permiso GPS denegado"
                break
            case error.POSITION_UNAVAILABLE:
                message = "GPS no disponible"
                break
            case error.TIMEOUT:
                message = "GPS timeout"
                break
        }

        this.updateStatus("gps", message, "danger")
        this.showError(message)
    }

    async syncPositions() {
        if (this.positionQueue.length === 0) {
            console.log("⏭️ No hay posiciones para sincronizar")
            return
        }

        const positions = [...this.positionQueue]
        this.positionQueue = []

        console.log(`🔄 Sincronizando ${positions.length} posiciones...`)

        try {
            const response = await fetch(
                `/driver/delivery_plans/${this.deliveryPlanIdValue}/update_position_batch`,
                {
                    method: "PATCH",
                    headers: {
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    },
                    body: JSON.stringify({ positions })
                }
            )

            if (response.ok) {
                const data = await response.json()
                console.log(`✅ Sincronizado: ${data.accepted} aceptadas, ${data.rejected} rechazadas`)
                this.updateStatus("sync", "Sincronizado", "success")
            } else if (response.status === 403) {
                // Plan completado en el servidor
                console.log("🔒 Plan completado, deteniendo tracking")
                this.stopTracking()
            } else {
                console.error("❌ Error al sincronizar:", response.status)
                this.positionQueue.unshift(...positions)
                this.updateStatus("sync", "Error sync", "warning")
            }
        } catch (error) {
            console.error("❌ Error de red:", error)
            this.positionQueue.unshift(...positions)
            this.updateStatus("sync", "Sin conexión", "warning")
            this.saveToIndexedDB(positions)
        }
    }

    async saveToIndexedDB(positions) {
        console.log("💾 Guardando en IndexedDB para sincronizar después")
        // TODO: Implementar almacenamiento offline
    }

    updateStatus(type, text, variant = "info") {
        const element = document.getElementById(`${type}-status`)
        if (element) {
            element.textContent = text
            element.className = `badge bg-${variant}`
        }
    }

    updateLastPosition(lat, lng, timestamp) {
        const element = document.getElementById("last-position-update")
        if (element) {
            const date = new Date(timestamp)
            element.textContent = date.toLocaleTimeString()
        }

        const latElement = document.getElementById("current-latitude")
        const lngElement = document.getElementById("current-longitude")
        if (latElement) latElement.textContent = lat.toFixed(6)
        if (lngElement) lngElement.textContent = lng.toFixed(6)
    }

    showError(message) {
        console.error(message)
    }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content
    }
}