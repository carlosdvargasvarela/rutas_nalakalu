// app/javascript/controllers/driver_tracker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        planId: Number,
        updateUrl: String,
        intervalMs: { type: Number, default: 30000 },
        minDistance: { type: Number, default: 50 }
    }

    connect() {
        console.log('[Tracker] Connected')
        this.lastPosition = null
        this.watchId = null
        this.fallbackIntervalId = null
        this.isTracking = false

        // Escuchar eventos del SW
        if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
            navigator.serviceWorker.addEventListener('message', this.handleSWMessage.bind(this))
        }
    }

    disconnect() {
        this.stopTracking()
    }

    startTracking() {
        if (this.isTracking) return

        console.log('[Tracker] Starting tracking...')
        this.isTracking = true

        if (!navigator.geolocation) {
            console.error('[Tracker] Geolocation not supported')
            return
        }

        // Intentar watchPosition primero
        try {
            this.watchId = navigator.geolocation.watchPosition(
                this.handlePosition.bind(this),
                this.handleError.bind(this),
                {
                    enableHighAccuracy: true,
                    maximumAge: 5000,
                    timeout: 10000
                }
            )
            console.log('[Tracker] Using watchPosition')
        } catch (error) {
            console.warn('[Tracker] watchPosition failed, using polling fallback:', error)
            this.startPolling()
        }
    }

    stopTracking() {
        console.log('[Tracker] Stopping tracking...')
        this.isTracking = false

        if (this.watchId !== null) {
            navigator.geolocation.clearWatch(this.watchId)
            this.watchId = null
        }

        if (this.fallbackIntervalId !== null) {
            clearInterval(this.fallbackIntervalId)
            this.fallbackIntervalId = null
        }
    }

    startPolling() {
        this.fallbackIntervalId = setInterval(() => {
            navigator.geolocation.getCurrentPosition(
                this.handlePosition.bind(this),
                this.handleError.bind(this),
                {
                    enableHighAccuracy: true,
                    maximumAge: 5000,
                    timeout: 10000
                }
            )
        }, this.intervalMsValue)
    }

    handlePosition(position) {
        const { latitude, longitude, speed, heading, accuracy } = position.coords

        // Filtrar por distancia mínima
        if (this.lastPosition) {
            const distance = this.calculateDistance(
                this.lastPosition.latitude,
                this.lastPosition.longitude,
                latitude,
                longitude
            )

            if (distance < this.minDistanceValue) {
                console.log('[Tracker] Position change too small, skipping:', distance)
                return
            }
        }

        console.log('[Tracker] New position:', { latitude, longitude, speed, heading, accuracy })

        this.lastPosition = { latitude, longitude, speed, heading, accuracy }

        // Enviar al servidor (el SW interceptará si offline)
        this.sendPosition(latitude, longitude, speed, heading, accuracy)
    }

    handleError(error) {
        console.error('[Tracker] Geolocation error:', error.message)

        // Si watchPosition falla, intentar polling
        if (this.watchId !== null && this.fallbackIntervalId === null) {
            console.log('[Tracker] Switching to polling fallback')
            navigator.geolocation.clearWatch(this.watchId)
            this.watchId = null
            this.startPolling()
        }
    }

    async sendPosition(latitude, longitude, speed, heading, accuracy) {
        const url = this.updateUrlValue

        const payload = {
            latitude: latitude,
            longitude: longitude,
            speed: speed,
            heading: heading,
            accuracy: accuracy,
            timestamp: new Date().toISOString()
        }

        try {
            const response = await fetch(url, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'X-CSRF-Token': this.getCSRFToken()
                },
                body: JSON.stringify(payload)
            })

            const data = await response.json()

            if (data.queued) {
                console.log('[Tracker] Position queued for sync')
                this.showQueuedIndicator()
            } else if (response.ok) {
                console.log('[Tracker] Position sent successfully')
            } else {
                console.error('[Tracker] Failed to send position:', response.status)
            }
        } catch (error) {
            console.error('[Tracker] Network error sending position:', error)
        }
    }

    handleSWMessage(event) {
        const { type, planId, count } = event.data

        if (type === 'POSITIONS_FLUSHED' && planId == this.planIdValue) {
            console.log(`[Tracker] ${count} positions synced from queue`)
            this.hideQueuedIndicator()
        }
    }

    showQueuedIndicator() {
        // Opcional: mostrar badge o ícono de "sincronizando"
        const indicator = document.querySelector('[data-sync-indicator]')
        if (indicator) {
            indicator.classList.remove('d-none')
        }
    }

    hideQueuedIndicator() {
        const indicator = document.querySelector('[data-sync-indicator]')
        if (indicator) {
            indicator.classList.add('d-none')
        }
    }

    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371e3 // Radio de la Tierra en metros
        const φ1 = lat1 * Math.PI / 180
        const φ2 = lat2 * Math.PI / 180
        const Δφ = (lat2 - lat1) * Math.PI / 180
        const Δλ = (lon2 - lon1) * Math.PI / 180

        const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2)
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

        return R * c // Distancia en metros
    }

    getCSRFToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content || ''
    }
}