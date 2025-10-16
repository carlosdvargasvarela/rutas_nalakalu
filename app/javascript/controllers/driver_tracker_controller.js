import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        deliveryPlanId: Number,
        intervalMs: { type: Number, default: 30000 },
        minDistance: { type: Number, default: 50 }
    }

    connect() {
        this._lastPos = null
        this._timer = null

        // Validación: asegurar que tengamos plan id
        if (!this.hasDeliveryPlanIdValue) {
            console.error("driver-tracker: falta deliveryPlanIdValue en data-driver-tracker-delivery-plan-id-value")
            return
        }

        // Solo iniciar si el plan está in_progress
        const planStatus = this._getPlanStatus()
        if (planStatus === "in_progress") {
            this._start()
        }

        // Escuchar cambios de estado del plan
        this._onPlanStatusChangedBound = this._onPlanStatusChanged.bind(this)
        document.addEventListener("driver:plan:status-changed", this._onPlanStatusChangedBound)
    }

    disconnect() {
        this._stop()
        if (this._onPlanStatusChangedBound) {
            document.removeEventListener("driver:plan:status-changed", this._onPlanStatusChangedBound)
        }
    }

    _onPlanStatusChanged(event) {
        const { status } = event.detail
        if (status === "in_progress") {
            this._start()
        } else {
            this._stop()
        }
    }

    _getPlanStatus() {
        const planEl = document.querySelector('[data-controller~="driver-plan"]')
        // En Stimulus v3 los values quedan como data-driver-plan-status-value
        return planEl?.dataset.driverPlanStatusValue || planEl?.dataset.status || ""
    }

    _start() {
        if (!("geolocation" in navigator)) return
        if (this._timer) return // Ya está corriendo

        // Primer tick inmediato
        this._tick()
        // Luego por intervalo
        this._timer = setInterval(() => this._tick(), this.intervalMsValue)
    }

    _stop() {
        if (this._timer) clearInterval(this._timer)
        this._timer = null
    }

    async _tick() {
        try {
            const pos = await this._getPosition({
                enableHighAccuracy: true,
                timeout: 10000,
                maximumAge: 0
            })

            if (!this._shouldSend(pos)) return

            const payload = {
                position: {
                    lat: pos.coords.latitude,
                    lng: pos.coords.longitude,
                    speed: pos.coords.speed ?? null,
                    heading: pos.coords.heading ?? null,
                    accuracy: pos.coords.accuracy ?? null,
                    at: new Date(pos.timestamp).toISOString()
                }
            }

            const url = `/driver/delivery_plans/${this.deliveryPlanIdValue}/update_position.json`
            const headers = this._defaultHeaders()

            const res = await fetch(url, {
                method: "PATCH",
                headers,
                body: JSON.stringify(payload)
            })

            // Si el SW encola, podría devolver 202
            if (res.ok || res.status === 202) {
                this._lastPos = pos
            }
        } catch (e) {
            // Offline o error de geolocalización: el SW puede encolar
            // Silencioso para no molestar al chofer
        }
    }

    _shouldSend(pos) {
        if (!this._lastPos) return true
        const dist = this._haversine(
            this._lastPos.coords.latitude, this._lastPos.coords.longitude,
            pos.coords.latitude, pos.coords.longitude
        )
        return dist >= this.minDistanceValue
    }

    _getPosition(opts) {
        return new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, opts)
        })
    }

    _haversine(lat1, lon1, lat2, lon2) {
        const toRad = (v) => (v * Math.PI) / 180
        const R = 6371000 // metros
        const dLat = toRad(lat2 - lat1)
        const dLon = toRad(lon2 - lon1)
        const a =
            Math.sin(dLat / 2) ** 2 +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) ** 2
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    _defaultHeaders() {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-CSRF-Token": token
        }
    }
}