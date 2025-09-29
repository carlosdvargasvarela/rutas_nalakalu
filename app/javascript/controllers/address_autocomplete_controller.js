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
        "selectedAddressInfo", "selectedAddressText"
    ]

    connect() {
        // Solo inicializar si el contenedor ya está visible
        if (this.isContainerVisible()) {
            this.initializeWhenReady()
        } else {
            console.log("📦 Contenedor oculto, esperando activación manual...")
        }
    }

    // Método público para inicializar cuando se muestra el contenedor
    initialize() {
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
        this.selectedAddressIdValue = addressId
        this.updateSelectedAddressInfo()

        if (this.map) {
            this.centerMapOnSelectedAddress()
        }
    }

    // 🔥 MÉTODO FALTANTE: Actualizar la información de dirección seleccionada
    updateSelectedAddressInfo() {
        const selectedAddress = this.getSelectedAddress()

        if (this.hasSelectedAddressInfoTarget && this.hasSelectedAddressTextTarget) {
            if (selectedAddress) {
                this.selectedAddressTextTarget.textContent = selectedAddress.address
                this.selectedAddressInfoTarget.style.display = "block"
            } else {
                this.selectedAddressInfoTarget.style.display = "none"
            }
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
        script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places&v=weekly`
        script.async = true
        script.defer = true
        script.onload = () => this.waitForGoogleMaps()
        script.onerror = () => {
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
                this.initMap()
            } else if (attempts >= maxAttempts) {
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
                return
            }

            // Determinar posición inicial
            const selectedAddress = this.getSelectedAddress()
            let initialLat = 9.93333  // San José por defecto
            let initialLng = -84.08333

            if (selectedAddress && selectedAddress.latitude && selectedAddress.longitude) {
                initialLat = parseFloat(selectedAddress.latitude)
                initialLng = parseFloat(selectedAddress.longitude)
            }

            // Inicializar mapa
            this.map = new google.maps.Map(this.mapTarget, {
                center: { lat: initialLat, lng: initialLng },
                zoom: selectedAddress ? 16 : 14, // Más zoom si hay dirección específica
                mapTypeControl: false,
                streetViewControl: false,
                fullscreenControl: false
            })

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
            this.fallbackToBasicInput()
        }
    }

    async createMarker(lat = 9.93333, lng = -84.08333) {
        try {
            // Intentar usar AdvancedMarkerElement (nuevo)
            if (google.maps.marker && google.maps.marker.AdvancedMarkerElement) {
                this.marker = new google.maps.marker.AdvancedMarkerElement({
                    map: this.map,
                    position: { lat, lng },
                    gmpDraggable: true,
                    title: "Ubicación de entrega"
                })

                this.marker.addListener("dragend", (event) => {
                    const newLat = event.latLng.lat()
                    const newLng = event.latLng.lng()
                    this.updateCoordinates(newLat, newLng, true)
                })

            } else {
                this.marker = new google.maps.Marker({
                    map: this.map,
                    position: { lat, lng },
                    draggable: true,
                    title: "Ubicación de entrega"
                })

                this.marker.addListener("dragend", (event) => {
                    const newLat = event.latLng.lat()
                    const newLng = event.latLng.lng()
                    this.updateCoordinates(newLat, newLng, true)
                })
            }

        } catch (error) {
            console.error("❌ Error creando marcador:", error)
        }
    }

    setupAutocomplete() {
        try {
            this.autocomplete = new google.maps.places.Autocomplete(this.inputTarget, {
                // 👇 Permitir direcciones, locales, POIs y establecimientos
                types: ["geocode", "establishment"],
                componentRestrictions: { country: "CR" },
                // 👇 Solicitar más campos incluyendo name y plus_code
                fields: [
                    "geometry",
                    "formatted_address",
                    "name",
                    "plus_code",
                    "place_id",
                    "types"
                ]
            })

            this.autocomplete.addListener("place_changed", () => {
                const place = this.autocomplete.getPlace()

                if (!place.geometry) {
                    return
                }

                const lat = place.geometry.location.lat()
                const lng = place.geometry.location.lng()

                // 🎯 Determinar qué mostrar en el input
                let displayAddress = ""

                // Si es un establecimiento/POI, mostrar el nombre + dirección
                if (place.name && place.types &&
                    (place.types.includes("establishment") ||
                        place.types.includes("point_of_interest") ||
                        place.types.includes("store"))) {
                    displayAddress = `${place.name} - ${place.formatted_address}`
                } else {
                    // Para direcciones normales, usar formatted_address
                    displayAddress = place.formatted_address
                }

                // Actualizar el input con la dirección mejorada
                this.inputTarget.value = displayAddress

                // 🎯 CAMBIO: NO llamar updateCoordinates aquí porque ya actualizamos el input
                // Solo actualizar coordenadas y plus code
                this.latTarget.value = lat
                this.lngTarget.value = lng

                // 🎯 Mejorar captura de Plus Code
                let plusCode = ""
                if (place.plus_code) {
                    // Preferir global_code, si no compound_code
                    plusCode = place.plus_code.global_code || place.plus_code.compound_code || ""
                }
                this.plusTarget.value = plusCode

                this.map.setCenter({ lat, lng })
                this.updateMarkerPosition(lat, lng)
            })

        } catch (error) {
            console.error("❌ Error configurando autocompletado:", error)
        }
    }

    // 🎯 CAMBIO: Agregar parámetro forceUpdateInput
    updateCoordinates(lat, lng, forceUpdateInput = false) {
        this.latTarget.value = lat
        this.lngTarget.value = lng
        this.reverseGeocode(lat, lng, forceUpdateInput)
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

    // 🎯 CAMBIO: Agregar parámetro forceUpdateInput
    reverseGeocode(lat, lng, forceUpdateInput = false) {
        if (!google.maps.Geocoder) return

        const geocoder = new google.maps.Geocoder()
        geocoder.geocode({ location: { lat, lng } }, (results, status) => {
            if (status === "OK" && results[0]) {
                // 🎯 LÓGICA MEJORADA: Actualizar input si se fuerza o está vacío
                if (forceUpdateInput || !this.inputTarget.value || this.inputTarget.value.trim() === "") {
                    this.inputTarget.value = results[0].formatted_address
                }

                // Actualizar plus code si no se tiene
                if (!this.plusTarget.value && results[0].plus_code) {
                    this.plusTarget.value = results[0].plus_code.global_code ||
                        results[0].plus_code.compound_code || ""
                }
            } else {
                console.warn("⚠️ Error en geocodificación inversa:", status)
            }
        })
    }

    refreshMap() {
        if (this.map) {
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