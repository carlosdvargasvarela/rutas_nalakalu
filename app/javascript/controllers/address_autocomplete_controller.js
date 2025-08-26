// app/javascript/controllers/address_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { apiKey: String }
    static targets = ["input", "lat", "lng", "plus", "map"]

    connect() {
        console.log("🚀 AddressAutocomplete conectado")
        // Solo inicializar si el contenedor ya está visible
        if (this.isContainerVisible()) {
            this.initializeWhenReady()
        } else {
            console.log("📦 Contenedor oculto, esperando activación manual...")
        }
    }

    // Método público para inicializar cuando se muestra el contenedor
    initialize() {
        console.log("🎯 Inicializando desde método público...")
        if (!this.map && this.isContainerVisible()) {
            this.initializeWhenReady()
        } else if (this.map) {
            this.refreshMap()
        }
    }

    isContainerVisible() {
        return this.element.offsetWidth > 0 &&
            this.element.offsetHeight > 0 &&
            this.element.style.display !== "none"
    }

    initializeWhenReady() {
        if (this.isGoogleMapsReady()) {
            console.log("✅ Google Maps listo, inicializando...")
            this.initMap()
        } else {
            console.log("⏳ Esperando Google Maps...")
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
        script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places&v=weekly`
        script.async = true
        script.defer = true
        script.onload = () => this.waitForGoogleMaps()
        script.onerror = () => {
            console.error("❌ Error cargando Google Maps")
            this.fallbackToBasicInput()
        }
        document.head.appendChild(script)
    }

    waitForGoogleMaps() {
        let attempts = 0
        const maxAttempts = 30 // Reducido de 50

        const checkGoogle = () => {
            attempts++
            if (this.isGoogleMapsReady()) {
                console.log("✅ Google Maps disponible!")
                this.initMap()
            } else if (attempts >= maxAttempts) {
                console.error("❌ Timeout esperando Google Maps")
                this.fallbackToBasicInput()
            } else {
                setTimeout(checkGoogle, 200) // Aumentado de 100ms
            }
        }
        checkGoogle()
    }

    isGoogleMapsReady() {
        return (
            typeof google !== "undefined" &&
            google.maps &&
            google.maps.Map &&
            google.maps.places &&
            google.maps.places.Autocomplete &&
            google.maps.Geocoder
        )
    }

    async initMap() {
        console.log("🗺️ Inicializando mapa...")

        try {
            // Verificar que el contenedor del mapa sea visible
            if (!this.isContainerVisible() || this.mapTarget.offsetWidth === 0) {
                console.warn("⚠️ Contenedor del mapa no visible")
                return
            }

            // Inicializar mapa
            this.map = new google.maps.Map(this.mapTarget, {
                center: { lat: 9.93333, lng: -84.08333 }, // San José, Costa Rica
                zoom: 14,
                mapTypeControl: false,
                streetViewControl: false,
                fullscreenControl: false
            })

            console.log("✅ Mapa creado")

            // Usar AdvancedMarkerElement si está disponible, sino Marker clásico
            await this.createMarker()

            // Configurar autocompletado
            this.setupAutocomplete()

        } catch (error) {
            console.error("❌ Error en initMap:", error)
            this.fallbackToBasicInput()
        }
    }

    async createMarker() {
        try {
            // Intentar usar AdvancedMarkerElement (nuevo)
            if (google.maps.marker && google.maps.marker.AdvancedMarkerElement) {
                console.log("✅ Usando AdvancedMarkerElement")

                this.marker = new google.maps.marker.AdvancedMarkerElement({
                    map: this.map,
                    position: { lat: 9.93333, lng: -84.08333 },
                    gmpDraggable: true,
                    title: "Ubicación de entrega"
                })

                // Listener para drag con AdvancedMarkerElement
                this.marker.addListener("dragend", (event) => {
                    const lat = event.latLng.lat()
                    const lng = event.latLng.lng()
                    console.log(`📍 Marcador movido a: ${lat}, ${lng}`)
                    this.updateCoordinates(lat, lng)
                })

            } else {
                // Fallback a Marker clásico
                console.log("⚠️ Usando Marker clásico (deprecated)")

                this.marker = new google.maps.Marker({
                    map: this.map,
                    position: { lat: 9.93333, lng: -84.08333 },
                    draggable: true,
                    title: "Ubicación de entrega"
                })

                // Listener para drag con Marker clásico
                this.marker.addListener("dragend", (event) => {
                    const lat = event.latLng.lat()
                    const lng = event.latLng.lng()
                    console.log(`📍 Marcador movido a: ${lat}, ${lng}`)
                    this.updateCoordinates(lat, lng)
                })
            }

            console.log("✅ Marcador creado")

        } catch (error) {
            console.error("❌ Error creando marcador:", error)
        }
    }

    setupAutocomplete() {
        console.log("🔍 Configurando autocompletado...")

        try {
            // Usar PlaceAutocompleteElement si está disponible
            if (google.maps.places.PlaceAutocompleteElement) {
                console.log("✅ Usando PlaceAutocompleteElement (nuevo)")
                this.setupNewAutocomplete()
            } else {
                console.log("⚠️ Usando Autocomplete clásico (deprecated)")
                this.setupClassicAutocomplete()
            }

        } catch (error) {
            console.error("❌ Error configurando autocompletado:", error)
            this.setupClassicAutocomplete() // Fallback
        }
    }

    setupNewAutocomplete() {
        // Implementación con PlaceAutocompleteElement
        // Nota: Esta API aún está en desarrollo, mantenemos el clásico por ahora
        this.setupClassicAutocomplete()
    }

    setupClassicAutocomplete() {
        this.autocomplete = new google.maps.places.Autocomplete(this.inputTarget, {
            types: ["geocode"],
            componentRestrictions: { country: "CR" },
            fields: ["geometry", "formatted_address", "plus_code"]
        })

        console.log("✅ Autocompletado creado")

        this.autocomplete.addListener("place_changed", () => {
            const place = this.autocomplete.getPlace()
            console.log("📍 Lugar seleccionado:", place)

            if (!place.geometry) {
                console.warn("⚠️ Sin información geográfica")
                return
            }

            const lat = place.geometry.location.lat()
            const lng = place.geometry.location.lng()

            this.updateCoordinates(lat, lng)
            this.plusTarget.value = place.plus_code?.compound_code || ""

            this.map.setCenter({ lat, lng })
            this.updateMarkerPosition(lat, lng)

            console.log(`✅ Coordenadas actualizadas: ${lat}, ${lng}`)
        })
    }

    updateCoordinates(lat, lng) {
        this.latTarget.value = lat
        this.lngTarget.value = lng
        this.reverseGeocode(lat, lng)
    }

    updateMarkerPosition(lat, lng) {
        if (this.marker) {
            if (this.marker.position) {
                // AdvancedMarkerElement
                this.marker.position = { lat, lng }
            } else {
                // Marker clásico
                this.marker.setPosition({ lat, lng })
            }
        }
    }

    reverseGeocode(lat, lng) {
        if (!google.maps.Geocoder) return

        const geocoder = new google.maps.Geocoder()
        geocoder.geocode({ location: { lat, lng } }, (results, status) => {
            if (status === "OK" && results[0]) {
                this.inputTarget.value = results[0].formatted_address
                this.plusTarget.value = results[0].plus_code?.compound_code || ""
                console.log("✅ Geocodificación inversa exitosa")
            } else {
                console.warn("⚠️ Error en geocodificación inversa:", status)
            }
        })
    }

    // Método para refrescar el mapa cuando se hace visible
    refreshMap() {
        if (this.map) {
            console.log("🔄 Refrescando mapa...")
            setTimeout(() => {
                google.maps.event.trigger(this.map, "resize")
                this.map.setCenter({ lat: 9.93333, lng: -84.08333 })
            }, 100)
        }
    }

    fallbackToBasicInput() {
        console.warn("⚠️ Usando fallback - input básico")
        if (this.mapTarget) {
            this.mapTarget.innerHTML = '<div class="alert alert-warning"><i class="bi bi-exclamation-triangle me-2"></i>Mapa no disponible. Ingrese la dirección manualmente.</div>'
        }
    }

    disconnect() {
        console.log("🔌 Desconectando AddressAutocomplete")

        // Limpiar listeners del marcador
        if (this.marker && google?.maps?.event) {
            google.maps.event.clearInstanceListeners(this.marker)
        }

        // Limpiar listeners del autocompletado
        if (this.autocomplete && google?.maps?.event) {
            google.maps.event.clearInstanceListeners(this.autocomplete)
        }

        // Limpiar timers si existen
        if (this.retryTimer) {
            clearTimeout(this.retryTimer)
            this.retryTimer = null
        }

        // Limpiar referencias
        this.map = null
        this.marker = null
        this.autocomplete = null
    }
}