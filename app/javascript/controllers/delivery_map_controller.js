// app/javascript/controllers/delivery_plan_map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map"]
  static values = {
    apiKey: String,
    points: Array,
    optimize: { type: Boolean, default: false }
  }

  connect() {
    if (this.isGoogleMapsReady()) {
      this.initMap()
    } else {
      this.loadGoogleMaps()
    }
  }

  loadGoogleMaps() {
    if (document.querySelector("#google-maps-script")) {
      this.waitForGoogleMaps()
      return
    }
    const s = document.createElement("script")
    s.id = "google-maps-script"
    s.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}`
    s.async = true
    s.defer = true
    s.onload = () => this.waitForGoogleMaps()
    document.head.appendChild(s)
  }

  waitForGoogleMaps() {
    const check = () => {
      if (this.isGoogleMapsReady()) {
        this.initMap()
      } else {
        setTimeout(check, 200)
      }
    }
    check()
  }

  isGoogleMapsReady() {
    return typeof google !== "undefined" && google.maps
  }

  initMap() {
    if (!this.pointsValue?.length) return

    const first = this.normalizePoint(this.pointsValue[0])
    this.map = new google.maps.Map(this.mapTarget, {
      center: first,
      zoom: 12,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false
    })

    this.bounds = new google.maps.LatLngBounds()
    this.markers = this.addMarkers()

    // Dibuja la ruta por carretera usando Directions segmentado
    this.drawDirectionsRouteWithChunks()
  }

  normalizePoint(p) {
    return {
      lat: typeof p.lat === "string" ? parseFloat(p.lat) : p.lat,
      lng: typeof p.lng === "string" ? parseFloat(p.lng) : p.lng
    }
  }

  addMarkers() {
    const markers = []
    this.pointsValue.forEach((p, idx) => {
      const pos = this.normalizePoint(p)
      const label = String(p.stop_order || idx + 1)
      const marker = new google.maps.Marker({
        position: pos,
        label,
        map: this.map,
        title: `${p.order_number || ""} - ${p.client || ""}`.trim()
      })
      const infowindow = new google.maps.InfoWindow({
        content: `
          <div style="min-width:220px">
            <strong>Parada ${label}</strong><br>
            Pedido: ${p.order_number || "-"}<br>
            Cliente: ${p.client || "-"}<br>
            Dirección: ${p.address || "-"}<br>
            ${p.date ? `Fecha: ${p.date}` : ""}
          </div>
        `
      })
      marker.addListener("click", () => infowindow.open(this.map, marker))
      markers.push(marker)
      this.bounds.extend(pos)
    })
    this.map.fitBounds(this.bounds)
    return markers
  }

  // Segmenta en tramos: 1 origen + hasta 23 waypoints + 1 destino
  drawDirectionsRouteWithChunks() {
    const pts = this.pointsValue.map(p => this.normalizePoint(p))
    if (pts.length < 2) return

    const MAX_WAYPOINTS = 23 // intermedios (límite por request)
    const segments = []
    let startIndex = 0
    while (startIndex < pts.length - 1) {
      const endIndex = Math.min(startIndex + MAX_WAYPOINTS + 1, pts.length - 1)
      const segment = pts.slice(startIndex, endIndex + 1)
      segments.push(segment)
      startIndex = endIndex
    }

    this._directionsRenderers = []
    this._totalSegments = segments.length

    // Encadenar para respetar el orden y preservar viewport entre segmentos
    let chain = Promise.resolve()
    segments.forEach((segment, i) => {
      chain = chain.then(() => this.requestDirectionsSegment(segment, i, this._totalSegments))
    })
  }

  requestDirectionsSegment(segmentPoints, segmentIndex, totalSegments) {
    return new Promise((resolve) => {
      const origin = segmentPoints[0]
      const destination = segmentPoints[segmentPoints.length - 1]
      const inter = segmentPoints.slice(1, -1)
      const waypoints = inter.map(loc => ({ location: loc, stopover: true }))

      console.debug("Directions request segment", segmentIndex, {
        origin, destination, waypoints: waypoints.length
      })

      const directionsService = new google.maps.DirectionsService()
      const directionsRenderer = new google.maps.DirectionsRenderer({
        map: this.map,
        suppressMarkers: true,
        preserveViewport: true, // no reajustar entre segmentos
        polylineOptions: {
          strokeColor: "#007bff",
          strokeOpacity: 0.9,
          strokeWeight: 5
        }
      })
      this._directionsRenderers.push(directionsRenderer)

      const request = {
        origin,
        destination,
        waypoints,
        travelMode: google.maps.TravelMode.DRIVING,
        optimizeWaypoints: segmentIndex === 0 ? this.optimizeValue : false,
        // Nota: drivingOptions requiere fecha presente/futura
        drivingOptions: { departureTime: new Date() }
      }

      directionsService.route(request, (result, status) => {
        console.debug(`Directions status (segment ${segmentIndex}):`, status, result)
        if (status === "OK") {
          directionsRenderer.setDirections(result)
          // Solo ajustar el mapa al finalizar el último segmento
          if (segmentIndex === totalSegments - 1) {
            const lastBounds = result?.routes?.[0]?.bounds
            if (lastBounds) this.map.fitBounds(lastBounds)
          }
        } else {
          console.warn(`FALLBACK Polyline (segment ${segmentIndex}):`, status)
          // Dibuja recta para ESTE SEGMENTO únicamente (visible para diagnosticar)
          this.drawFallbackPolyline(segmentPoints)
          if (segmentIndex === totalSegments - 1) {
            segmentPoints.forEach(p => this.bounds.extend(p))
            this.map.fitBounds(this.bounds)
          }
        }
        resolve()
      })
    })
  }

  drawFallbackPolyline(points) {
    new google.maps.Polyline({
      path: points,
      geodesic: true,
      strokeColor: "#ff4d4f",
      strokeOpacity: 0.7,
      strokeWeight: 3,
      map: this.map
    })
  }
}