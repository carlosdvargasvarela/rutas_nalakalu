import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map"]
  static values = {
    apiKey: String,
    points: Array
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
    const script = document.createElement("script")
    script.id = "google-maps-script"
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=geometry`
    script.async = true
    script.defer = true
    script.onload = () => this.waitForGoogleMaps()
    document.head.appendChild(script)
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
    if (!this.pointsValue.length) return

    const center = {
      lat: parseFloat(this.pointsValue[0].lat),
      lng: parseFloat(this.pointsValue[0].lng)
    }

    this.map = new google.maps.Map(this.mapTarget, {
      center,
      zoom: 12,
      mapTypeControl: false
    })

    this.bounds = new google.maps.LatLngBounds()
    this.addMarkers()
    this.drawPolyline()
    this.map.fitBounds(this.bounds)
  }

  addMarkers() {
    this.pointsValue.forEach((p, idx) => {
      const position = { lat: parseFloat(p.lat), lng: parseFloat(p.lng) }
      const marker = new google.maps.Marker({
        position,
        label: String(p.stop_order || idx + 1),
        map: this.map,
        title: `${p.order_number} - ${p.client}`
      })

      const infowindow = new google.maps.InfoWindow({
        content: `
          <div>
            <strong>Parada ${p.stop_order || idx + 1}</strong><br>
            Pedido: ${p.order_number}<br>
            Cliente: ${p.client}<br>
            Dirección: ${p.address}<br>
            Fecha: ${p.date}
          </div>
        `
      })

      marker.addListener("click", () => {
        infowindow.open(this.map, marker)
      })

      this.bounds.extend(position)
    })
  }

  drawPolyline() {
    const routePath = new google.maps.Polyline({
      path: this.pointsValue.map(p => ({
        lat: parseFloat(p.lat),
        lng: parseFloat(p.lng)
      })),
      geodesic: true,
      strokeColor: "#007bff",
      strokeOpacity: 0.7,
      strokeWeight: 3,
      map: this.map
    })
  }
}