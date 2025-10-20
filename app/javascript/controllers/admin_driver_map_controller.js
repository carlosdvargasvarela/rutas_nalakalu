// app/javascript/controllers/admin_driver_map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        deliveryPlanId: Number,
        currentLat: Number,
        currentLng: Number,
        assignments: Array
    }

    connect() {
        this.initMap()
        this.startPolling()

        // 🔁 Refrescar cuando se marque una entrega como fallida/completada
        window.addEventListener("assignment:updated", this.handleAssignmentUpdated)
    }

    disconnect() {
        window.removeEventListener("assignment:updated", this.handleAssignmentUpdated)
        this.stopPolling()
    }

    handleAssignmentUpdated = (event) => {
        const { assignment } = event.detail
        console.log("♻️ Cambio recibido en mapa Admin:", assignment)
        this.updateAssignmentStatuses([assignment])
    }

    async initMap() {
        // Esperar a que Google Maps esté cargado
        await this.waitForGoogleMaps()

        const defaultLat = this.currentLatValue || 9.9281
        const defaultLng = this.currentLngValue || -84.0907

        // Crear mapa
        this.map = new google.maps.Map(this.element, {
            center: { lat: defaultLat, lng: defaultLng },
            zoom: 13,
            mapTypeControl: true,
            streetViewControl: false,
            fullscreenControl: true
        })

        // Marcador del conductor (camión)
        this.driverMarker = new google.maps.Marker({
            position: { lat: defaultLat, lng: defaultLng },
            map: this.map,
            icon: {
                path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
                scale: 6,
                fillColor: "#0d6efd",
                fillOpacity: 1,
                strokeColor: "#ffffff",
                strokeWeight: 2,
                rotation: 0
            },
            title: "Conductor"
        })

        // Info window para el conductor
        this.driverInfoWindow = new google.maps.InfoWindow({
            content: this.getDriverInfoContent()
        })

        this.driverMarker.addListener("click", () => {
            this.driverInfoWindow.open(this.map, this.driverMarker)
        })

        // Marcadores de entregas
        this.deliveryMarkers = []
        this.assignmentsValue.forEach((assignment, index) => {
            const delivery = assignment.delivery
            if (delivery.latitude && delivery.longitude) {
                this.createDeliveryMarker(assignment, index + 1)
            }
        })

        // Línea de ruta
        this.routePath = new google.maps.Polyline({
            path: [],
            geodesic: true,
            strokeColor: "#0d6efd",
            strokeOpacity: 0.7,
            strokeWeight: 3,
            map: this.map
        })

        // Línea de historial (donde ya pasó)
        this.historyPath = new google.maps.Polyline({
            path: [],
            geodesic: true,
            strokeColor: "#6c757d",
            strokeOpacity: 0.5,
            strokeWeight: 2,
            map: this.map
        })

        this.updateRouteLine()
    }

    createDeliveryMarker(assignment, stopNumber) {
        const delivery = assignment.delivery
        const position = {
            lat: parseFloat(delivery.latitude),
            lng: parseFloat(delivery.longitude)
        }

        const marker = new google.maps.Marker({
            position: position,
            map: this.map,
            label: {
                text: stopNumber.toString(),
                color: "#ffffff",
                fontWeight: "bold"
            },
            icon: {
                path: google.maps.SymbolPath.CIRCLE,
                scale: 12,
                fillColor: this.getMarkerColor(assignment.status),
                fillOpacity: 1,
                strokeColor: "#ffffff",
                strokeWeight: 2
            },
            title: delivery.customer.name
        })

        const infoWindow = new google.maps.InfoWindow({
            content: `
        <div style="padding: 8px;">
          <strong>Parada ${stopNumber}</strong><br>
          ${delivery.customer.name}<br>
          <span class="badge bg-${this.getStatusBadge(assignment.status)}">${assignment.status}</span>
        </div>
      `
        })

        marker.addListener("click", () => {
            infoWindow.open(this.map, marker)
        })

        this.deliveryMarkers.push({ marker, assignment })
    }

    getMarkerColor(status) {
        const colors = {
            pending: "#6c757d",
            in_route: "#ffc107",
            completed: "#198754",
            cancelled: "#dc3545"
        }
        return colors[status] || "#6c757d"
    }

    getStatusBadge(status) {
        const badges = {
            pending: "secondary",
            in_route: "warning",
            completed: "success",
            cancelled: "danger"
        }
        return badges[status] || "secondary"
    }

    getDriverInfoContent() {
        return `
      <div style="padding: 8px;">
        <strong>🚚 Conductor</strong><br>
        <small>Última actualización: <span id="driver-last-seen">--</span></small>
      </div>
    `
    }

    updateRouteLine() {
        const routePoints = []
        const bounds = new google.maps.LatLngBounds()

        // Posición actual del conductor
        if (this.currentLatValue && this.currentLngValue) {
            const driverPos = { lat: this.currentLatValue, lng: this.currentLngValue }
            routePoints.push(driverPos)
            bounds.extend(driverPos)
        }

        // Entregas pendientes en orden
        this.assignmentsValue
            .filter(a => a.status === "pending" || a.status === "in_route")
            .forEach(assignment => {
                const delivery = assignment.delivery
                if (delivery.latitude && delivery.longitude) {
                    const pos = {
                        lat: parseFloat(delivery.latitude),
                        lng: parseFloat(delivery.longitude)
                    }
                    routePoints.push(pos)
                    bounds.extend(pos)
                }
            })

        this.routePath.setPath(routePoints)

        if (routePoints.length > 0) {
            this.map.fitBounds(bounds, { padding: 50 })
        }
    }

    startPolling() {
        this.pollInterval = setInterval(() => {
            this.fetchCurrentPosition()
        }, 10000) // Cada 10 segundos
    }

    stopPolling() {
        if (this.pollInterval) {
            clearInterval(this.pollInterval)
        }
    }

    async fetchCurrentPosition() {
        try {
            const response = await fetch(`/delivery_plans/${this.deliveryPlanIdValue}.json`)
            const data = await response.json()

            if (data.current_lat && data.current_lng) {
                this.updateDriverPosition(data.current_lat, data.current_lng)
                this.updateLastSeenTime(data.last_seen_at)
            }

            if (data.assignments) {
                this.updateAssignmentStatuses(data.assignments)
            }
        } catch (error) {
            console.error("Error fetching position:", error)
        }
    }

    updateDriverPosition(lat, lng) {
        this.currentLatValue = lat
        this.currentLngValue = lng

        const newPosition = { lat, lng }
        this.driverMarker.setPosition(newPosition)

        // Centrar mapa suavemente
        this.map.panTo(newPosition)

        this.updateRouteLine()
    }

    updateLastSeenTime(timestamp) {
        if (timestamp) {
            const date = new Date(timestamp)
            const now = new Date()
            const diffSeconds = Math.floor((now - date) / 1000)

            let timeText
            if (diffSeconds < 60) {
                timeText = "Hace unos segundos"
            } else if (diffSeconds < 3600) {
                timeText = `Hace ${Math.floor(diffSeconds / 60)} minutos`
            } else {
                timeText = date.toLocaleTimeString()
            }

            const element = document.getElementById("driver-last-seen")
            if (element) {
                element.textContent = timeText
            }
        }
    }

    updateAssignmentStatuses(assignments) {
        assignments.forEach(assignment => {
            const markerData = this.deliveryMarkers.find(m => m.assignment.id === assignment.id)
            if (markerData) {
                markerData.assignment.status = assignment.status
                markerData.marker.setIcon({
                    ...markerData.marker.getIcon(),
                    fillColor: this.getMarkerColor(assignment.status)
                })
            }
        })

        this.updateRouteLine()
    }

    async waitForGoogleMaps() {
        return new Promise((resolve) => {
            if (window.google && window.google.maps) {
                resolve()
            } else {
                const checkInterval = setInterval(() => {
                    if (window.google && window.google.maps) {
                        clearInterval(checkInterval)
                        resolve()
                    }
                }, 100)
            }
        })
    }
}