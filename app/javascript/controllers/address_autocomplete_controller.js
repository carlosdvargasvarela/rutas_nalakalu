// app/javascript/controllers/address_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        apiKey: String,
        addresses: Array,
        selectedAddressId: String
    }
    static targets = [
        "input", "lat", "lng", "plus", "map",
        "selectedAddressInfo", "selectedAddressText", "useSelectedButton"
    ]

    connect() {
        console.log("🚀 AddressAutocomplete conectado")
        console.log("📍 Direcciones disponibles:", this.addressesValue)
        console.log("🎯 Dirección seleccionada ID:", this.selectedAddressIdValue)

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

        // Mostrar información de dirección seleccionada
        this.updateSelectedAddressInfo()
    }

    // Método llamado desde delivery-form cuando cambia el select
    updateSelectedAddress(addressId) {
        console.log("🔄 Actualizando dirección seleccionada:", addressId)
        this.selectedAddressIdValue = addressId
        this.updateSelectedAddressInfo()

        if (this.map) {
            this.centerMapOnSelectedAddress()
        }
    }

    updateSelectedAddressInfo() {
        const selectedAddress = this.getSelectedAddress()

        if (selectedAddress) {
            this.selectedAddressTextTarget.textContent = selectedAddress.address
            this.selectedAddressInfoTarget.style.display = "block"
            this.useSelectedButtonTarget.style.display = "inline-block"
            console.log("✅ Información de dirección actualizada:", selectedAddress.address)
        } else {
            this.selectedAddressInfoTarget.style.display = "none"
            this.useSelectedButtonTarget.style.display = "none"
        }
    }

    getSelectedAddress() {
        if (!this.selectedAddressIdValue || this.selectedAddressIdValue === "") {
            return null
        }

        return this.addressesValue.find(addr =>
            addr.id.toString() === this.selectedAddressIdValue.toString()
        )
    }

    centerMapOnSelectedAddress() {
        const selectedAddress = this.getSelectedAddress()

        if (selectedAddress && selectedAddress.latitude && selectedAddress.longitude) {
            const lat = parseFloat(selectedAddress.latitude)
            const lng = parseFloat(selectedAddress.longitude)

            console.log(`🗺️ Centrando mapa en dirección seleccionada: ${lat}, ${lng}`)

            this.map.setCenter({ lat, lng })
            this.updateMarkerPosition(lat, lng)

            // Actualizar campos ocultos
            this.latTarget.value = lat
            this.lngTarget.value = lng

            // Actualizar input de dirección
            this.inputTarget.value = selectedAddress.address
        }
    }

    useSelectedAddress() {
        const selectedAddress = this.getSelectedAddress()

        if (selectedAddress) {
            console.log("✅ Usando dirección seleccionada")

            // Llenar todos los campos
            this.inputTarget.value = selectedAddress.address

            if (selectedAddress.latitude && selectedAddress.longitude) {
                const lat = parseFloat(selectedAddress.latitude)
                const lng = parseFloat(selectedAddress.longitude)

                this.latTarget.value = lat
                this.lngTarget.value = lng

                if (this.map) {
                    this.map.setCenter({ lat, lng })
                    this.updateMarkerPosition(lat, lng)
                }
            }

            // Mostrar mensaje de confirmación
            this.showTemporaryMessage("✅ Dirección aplicada correctamente")
        }
    }

    clearForm() {
        console.log("🧹 Limpiando formulario")

        this.inputTarget.value = ""
        this.latTarget.value = ""
        this.lngTarget.value = ""
        this.plusTarget.value = ""

        // Resetear mapa a Costa Rica
        if (this.map) {
            this.map.setCenter({ lat: 9.93333, lng: -84.08333 })
            this.updateMarkerPosition(9.93333, -84.08333)
        }

        this.showTemporaryMessage("🧹 Formulario limpiado")
    }

    showTemporaryMessage(message) {
        // Crear elemento temporal para mostrar mensaje
        const messageDiv = document.createElement("div")
        messageDiv.className = "alert alert-success alert-dismissible fade show mt-2"
        messageDiv.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `

        this.element.appendChild(messageDiv)

        // Auto-remover después de 3 segundos
        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.remove()
            }
        }, 3000)
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
        const maxAttempts = 30

        const checkGoogle = () => {
            attempts++
            if (this.isGoogleMapsReady()) {
                console.log("✅ Google Maps disponible!")
                this.initMap()
            } else if (attempts >= maxAttempts) {
                console.error("❌ Timeout esperando Google Maps")
                this.fallbackToBasicInput()
            } else {
                setTimeout(checkGoogle, 200)
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
            if (!this.isContainerVisible() || this.mapTarget.offsetWidth === 0) {
                console.warn("⚠️ Contenedor del mapa no visible")
                return
            }

            // Determinar posición inicial
            const selectedAddress = this.getSelectedAddress()
            let initialLat = 9.93333  // San José por defecto
            let initialLng = -84.08333

            if (selectedAddress && selectedAddress.latitude && selectedAddress.longitude) {
                initialLat = parseFloat(selectedAddress.latitude)
                initialLng = parseFloat(selectedAddress.longitude)
                console.log(`🎯 Usando posición de dirección seleccionada: ${initialLat}, ${initialLng}`)
            }

            // Inicializar mapa
            this.map = new google.maps.Map(this.mapTarget, {
                center: { lat: initialLat, lng: initialLng },
                zoom: selectedAddress ? 16 : 14, // Más zoom si hay dirección específica
                mapTypeControl: false,
                streetViewControl: false,
                fullscreenControl: false
            })

            console.log("✅ Mapa creado")

            // Crear marcador
            await this.createMarker(initialLat, initialLng)

            // Configurar autocompletado
            this.setupAutocomplete()

            // Actualizar campos si hay dirección seleccionada
            if (selectedAddress) {
                this.latTarget.value = initialLat
                this.lngTarget.value = initialLng
                this.inputTarget.value = selectedAddress.address
            }

        } catch (error) {
            console.error("❌ Error en initMap:", error)
            this.fallbackToBasicInput()
        }
    }

    async createMarker(lat = 9.93333, lng = -84.08333) {
        try {
            // Intentar usar AdvancedMarkerElement (nuevo)
            if (google.maps.marker && google.maps.marker.AdvancedMarkerElement) {
                console.log("✅ Usando AdvancedMarkerElement")

                this.marker = new google.maps.marker.AdvancedMarkerElement({
                    map: this.map,
                    position: { lat, lng },
                    gmpDraggable: true,
                    title: "Ubicación de entrega"
                })

                this.marker.addListener("dragend", (event) => {
                    const newLat = event.latLng.lat()
                    const newLng = event.latLng.lng()
                    console.log(`📍 Marcador movido a: ${newLat}, ${newLng}`)
                    this.updateCoordinates(newLat, newLng)
                })

            } else {
                console.log("⚠️ Usando Marker clásico (deprecated)")

                this.marker = new google.maps.Marker({
                    map: this.map,
                    position: { lat, lng },
                    draggable: true,
                    title: "Ubicación de entrega"
                })

                this.marker.addListener("dragend", (event) => {
                    const newLat = event.latLng.lat()
                    const newLng = event.latLng.lng()
                    console.log(`📍 Marcador movido a: ${newLat}, ${newLng}`)
                    this.updateCoordinates(newLat, newLng)
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
            this.autocomplete = new google.maps.places.Autocomplete(this.inputTarget, {
                types: ["geocode"],
                componentRestrictions: { country: "CR" },
                fields: ["geometry", "formatted_address", "plus_code"]
            })

            console.log("✅ Autocompletado creado")

            this.autocomplete.addListener("place_changed", () => {
                const place = this.autocomplete.getPlace()
                console.log("📍 Lugar seleccionado desde autocomplete:", place)

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

                console.log(`✅ Coordenadas actualizadas desde autocomplete: ${lat}, ${lng}`)
            })

        } catch (error) {
            console.error("❌ Error configurando autocompletado:", error)
        }
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

    refreshMap() {
        if (this.map) {
            console.log("🔄 Refrescando mapa...")
            setTimeout(() => {
                google.maps.event.trigger(this.map, "resize")

                // Si hay dirección seleccionada, centrar ahí
                const selectedAddress = this.getSelectedAddress()
                if (selectedAddress && selectedAddress.latitude && selectedAddress.longitude) {
                    const lat = parseFloat(selectedAddress.latitude)
                    const lng = parseFloat(selectedAddress.longitude)
                    this.map.setCenter({ lat, lng })
                } else {
                    this.map.setCenter({ lat: 9.93333, lng: -84.08333 })
                }
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

        if (this.marker && google?.maps?.event) {
            google.maps.event.clearInstanceListeners(this.marker)
        }

        if (this.autocomplete && google?.maps?.event) {
            google.maps.event.clearInstanceListeners(this.autocomplete)
        }

        if (this.retryTimer) {
            clearTimeout(this.retryTimer)
            this.retryTimer = null
        }

        this.map = null
        this.marker = null
        this.autocomplete = null
    }
}