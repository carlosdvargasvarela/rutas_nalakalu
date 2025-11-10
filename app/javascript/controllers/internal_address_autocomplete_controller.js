import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "description", "map", "lat", "lng", "plus"];
  static values = {
    apiKey: String,
  };

  connect() {
    console.log("InternalAddressAutocompleteController connected");
    this.loadGoogleMapsAPI();
  }

  loadGoogleMapsAPI() {
    if (window.google && window.google.maps) {
      this.initializeAutocomplete();
      return;
    }

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker&callback=initInternalAddressAutocomplete`;
    script.async = true;
    script.defer = true;

    window.initInternalAddressAutocomplete = () => {
      this.initializeAutocomplete();
    };

    document.head.appendChild(script);
  }

  async initializeAutocomplete() {
    if (!this.hasInputTarget || !this.hasMapTarget) return;

    const { Map } = await google.maps.importLibrary("maps");
    const { AdvancedMarkerElement } = await google.maps.importLibrary("marker");

    this.map = new Map(this.mapTarget, {
      center: { lat: 9.9281, lng: -84.0907 },
      zoom: 13,
      mapId: "INTERNAL_DELIVERY_MAP_ID",
      mapTypeControl: false,
      streetViewControl: false,
    });

    this.marker = new AdvancedMarkerElement({
      map: this.map,
      position: { lat: 9.9281, lng: -84.0907 },
      gmpDraggable: true,
    });

    this.marker.addListener("dragend", (event) => {
      const position = event.latLng;
      this.updateCoordinates(position.lat(), position.lng());
      this.reverseGeocode(position);
    });

    // Inicializar Geocoder
    this.geocoder = new google.maps.Geocoder();

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

      if (!place.geometry) return;

      const location = place.geometry.location;

      this.map.setCenter(location);
      this.map.setZoom(17);
      this.marker.position = location;

      this.updateCoordinates(location.lat(), location.lng());

      if (place.plus_code && this.hasPlusTarget) {
        this.plusTarget.value =
          place.plus_code.global_code || place.plus_code.compound_code || "";
      }
    });
  }

  updateCoordinates(lat, lng) {
    if (this.hasLatTarget) this.latTarget.value = lat.toFixed(7);
    if (this.hasLngTarget) this.lngTarget.value = lng.toFixed(7);
  }

  async updateMapFromCoordinates(event) {
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
    this.map.setCenter(position);
    this.map.setZoom(17);
    this.marker.position = position;

    // Hacer reverse geocoding
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

        // Actualizar Plus Code
        if (result.plus_code && this.hasPlusTarget) {
          this.plusTarget.value =
            result.plus_code.global_code ||
            result.plus_code.compound_code ||
            "";
        }

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

  showCoordinateWarning(message) {
    let warning = document.getElementById("internal-coordinate-warning");

    if (!warning) {
      warning = document.createElement("div");
      warning.id = "internal-coordinate-warning";
      warning.className =
        "alert alert-warning alert-dismissible fade show mt-2";

      const detailsElement = this.element.querySelector("details .card-body");
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
