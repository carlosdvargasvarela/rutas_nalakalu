import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "map",
    "lat",
    "lng",
    "plus",
    "selectedAddressInfo",
    "selectedAddressText",
  ];
  static values = {
    apiKey: String,
  };

  connect() {
    console.log("AddressAutocompleteController connected");
    this.loadGoogleMapsAPI();
  }

  loadGoogleMapsAPI() {
    if (window.google && window.google.maps) {
      this.initializeAutocomplete();
      return;
    }

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker&callback=initAddressAutocomplete`;
    script.async = true;
    script.defer = true;

    window.initAddressAutocomplete = () => {
      this.initializeAutocomplete();
    };

    document.head.appendChild(script);
  }

  async initializeAutocomplete() {
    if (!this.hasInputTarget || !this.hasMapTarget) return;

    const { Map } = await google.maps.importLibrary("maps");
    const { AdvancedMarkerElement } = await google.maps.importLibrary("marker");

    // Inicializar mapa
    this.map = new Map(this.mapTarget, {
      center: { lat: 9.9281, lng: -84.0907 },
      zoom: 13,
      mapId: "DELIVERY_ADDRESS_MAP_ID",
      mapTypeControl: false,
      streetViewControl: false,
    });

    // Inicializar marcador
    this.marker = new AdvancedMarkerElement({
      map: this.map,
      position: { lat: 9.9281, lng: -84.0907 },
      gmpDraggable: true,
    });

    // Evento cuando se arrastra el marcador
    this.marker.addListener("dragend", (event) => {
      const position = event.latLng;
      this.updateCoordinates(position.lat(), position.lng());
      this.reverseGeocode(position);
    });

    // Inicializar Geocoder
    this.geocoder = new google.maps.Geocoder();

    // Inicializar Autocomplete
    this.autocomplete = new google.maps.places.Autocomplete(this.inputTarget, {
      componentRestrictions: { country: "cr" },
      fields: [
        "address_components",
        "geometry",
        "name",
        "formatted_address",
        "plus_code",
      ],
    });

    this.autocomplete.addListener("place_changed", () => {
      const place = this.autocomplete.getPlace();

      if (!place.geometry) {
        console.warn("No se encontró geometría para el lugar seleccionado");
        return;
      }

      const location = place.geometry.location;

      // Actualizar mapa
      this.map.setCenter(location);
      this.map.setZoom(17);
      this.marker.position = location;

      // Actualizar coordenadas
      this.updateCoordinates(location.lat(), location.lng());

      // Actualizar Plus Code
      if (place.plus_code && this.hasPlusTarget) {
        this.plusTarget.value =
          place.plus_code.global_code || place.plus_code.compound_code || "";
      }

      // Mostrar info de dirección seleccionada
      this.showSelectedAddressInfo(place.formatted_address || place.name);
    });
  }

  updateCoordinates(lat, lng) {
    if (this.hasLatTarget) this.latTarget.value = lat.toFixed(7);
    if (this.hasLngTarget) this.lngTarget.value = lng.toFixed(7);
  }

  async updateMapFromCoordinates(event) {
    // Validar que ambos campos tengan valores
    if (!this.hasLatTarget || !this.hasLngTarget) return;

    const lat = parseFloat(this.latTarget.value);
    const lng = parseFloat(this.lngTarget.value);

    if (isNaN(lat) || isNaN(lng)) {
      console.warn("Coordenadas inválidas");
      return;
    }

    // Validar rangos razonables para Costa Rica
    if (lat < 8 || lat > 11.5 || lng < -86 || lng > -82) {
      this.showCoordinateWarning(
        "Las coordenadas están fuera del rango de Costa Rica"
      );
      return;
    }

    const position = { lat, lng };

    // Actualizar mapa
    this.map.setCenter(position);
    this.map.setZoom(17);
    this.marker.position = position;

    // Hacer reverse geocoding para obtener la dirección
    await this.reverseGeocode(position);
  }

  async reverseGeocode(position) {
    if (!this.geocoder) {
      console.warn("Geocoder no inicializado");
      return;
    }

    try {
      const response = await this.geocoder.geocode({ location: position });

      if (response.results && response.results.length > 0) {
        const result = response.results[0];

        // Actualizar el campo de dirección con la dirección normalizada
        if (this.hasInputTarget) {
          this.inputTarget.value = result.formatted_address;

          // Disparar evento para validación
          this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }));
        }

        // Actualizar Plus Code si está disponible
        if (result.plus_code && this.hasPlusTarget) {
          this.plusTarget.value =
            result.plus_code.global_code ||
            result.plus_code.compound_code ||
            "";
        }

        // Mostrar info de dirección
        this.showSelectedAddressInfo(result.formatted_address);

        console.log("✅ Reverse geocoding exitoso:", result.formatted_address);
      } else {
        console.warn("No se encontraron resultados de reverse geocoding");
        this.showCoordinateWarning(
          "No se pudo obtener una dirección para estas coordenadas"
        );
      }
    } catch (error) {
      console.error("Error en reverse geocoding:", error);
      this.showCoordinateWarning(
        "Error al obtener la dirección. Verifique las coordenadas."
      );
    }
  }

  showSelectedAddressInfo(address) {
    if (!this.hasSelectedAddressInfoTarget) return;

    this.selectedAddressTextTarget.textContent = address;
    this.selectedAddressInfoTarget.style.display = "block";
  }

  showCoordinateWarning(message) {
    // Crear o actualizar alerta de advertencia
    let warning = document.getElementById("coordinate-warning");

    if (!warning) {
      warning = document.createElement("div");
      warning.id = "coordinate-warning";
      warning.className =
        "alert alert-warning alert-dismissible fade show mt-2";

      const detailsElement = this.element.querySelector("details");
      if (detailsElement) {
        detailsElement.appendChild(warning);
      }
    }

    warning.innerHTML = `
      <i class="bi bi-exclamation-triangle me-2"></i>
      <strong>Advertencia:</strong> ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `;
  }
}
