// app/javascript/controllers/delivery_map_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        const lat = parseFloat(this.element.dataset.lat)
        const lng = parseFloat(this.element.dataset.lng)

        if (!lat || !lng) {
            console.warn("No se encontraron coordenadas para mostrar en el mapa.")
            return
        }

        // Esperar a que Google Maps esté disponible
        this.initializeMap(lat, lng)
    }

    initializeMap(lat, lng) {
        if (typeof google !== 'undefined' && google.maps) {
            // Google Maps ya está cargado
            this.createMap(lat, lng)
        } else {
            // Esperar a que Google Maps se cargue
            const checkGoogleMaps = setInterval(() => {
                if (typeof google !== 'undefined' && google.maps) {
                    clearInterval(checkGoogleMaps)
                    this.createMap(lat, lng)
                }
            }, 100)
            
            // Timeout después de 10 segundos
            setTimeout(() => {
                clearInterval(checkGoogleMaps)
                console.error("Google Maps no se pudo cargar")
            }, 10000)
        }
    }

    createMap(lat, lng) {
        const map = new google.maps.Map(this.element, {
            center: { lat, lng },
            zoom: 15,
            mapTypeControl: false,
            streetViewControl: false,
            fullscreenControl: false
        })

        new google.maps.Marker({
            position: { lat, lng },
            map,
            title: "Dirección de entrega"
        })
    }
}