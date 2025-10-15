import { Controller } from "@hotwired/stimulus"

// Envía updates periódicos de geolocalización al endpoint update_position (JSON),
// encolándose si no hay conexión gracias al SW.
export default class extends Controller {
    static values = {
        deliveryPlanId: Number,
        intervalMs: { type: Number, default: 30000 }, // cada 30s
        minDistance: { type: Number, default: 50 }    // 50m
    }

    connect() {
        this._lastPos = null
        this._timer = null
        this._start()
    }

    disconnect() {
        this._stop()
    }

    _start() {
        if (!("geolocation" in navigator)) return
        this._tick() // primer intento inmediato
        this._timer = setInterval(() => this._tick(), this.intervalMsValue)
    }

    _stop() {
        if (this._timer) clearInterval(this._timer)
        this._timer = null
    }

    async _tick() {
        try {
            const pos = await this._getPosition({ enableHighAccuracy: true, timeout: 10000, maximumAge: 0 })
            if (!this._shouldSend(pos)) return

            const payload = {
                position: {
                    lat: pos.coords.latitude,
                    lng: pos.coords.longitude,
                    speed: pos.coords.speed || null,
                    heading: pos.coords.heading || null,
                    accuracy: pos.coords.accuracy || null,
                    at: new Date(pos.timestamp).toISOString()
                }
            }

            const url = `/driver/delivery_plans/${this.deliveryPlanIdValue}/update_position.json`
            const headers = this._defaultHeaders()
            headers["X-Request-Id"] = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`
            const res = await fetch(url, {
                method: "PATCH",
                headers,
                body: JSON.stringify(payload)
            })

            if (res.status === 202) {
                // encolado por SW
                // opcional: mostrar indicador sutil
            } else if (res.ok) {
                // OK
            }
            this._lastPos = pos
        } catch (e) {
            // offline → el SW encolará si está configurado para mutaciones
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
        const R = 6371000 // m
        const dLat = toRad(lat2 - lat1)
        const dLon = toRad(lon2 - lon1)
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2)
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