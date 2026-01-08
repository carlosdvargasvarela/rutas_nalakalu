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
    this._initialized = false;
    this._initAttempts = 0;

    this.loadGoogleMapsAPI().then(() => {
      this.tryInitializeAutocomplete();
      this.bindAccordionListener();
    });
  }

  disconnect() {
    this.unbindAccordionListener();

    if (this.autocomplete)
      google.maps.event.clearInstanceListeners(this.autocomplete);
    if (this.marker) google.maps.event.clearInstanceListeners(this.marker);
  }

  // ---------------------------------------------------------------------------
  // Script loader (single flight)
  // ---------------------------------------------------------------------------
  loadGoogleMapsAPI() {
    if (window.google && window.google.maps) return Promise.resolve();

    if (window.__googleMapsLoadingPromise)
      return window.__googleMapsLoadingPromise;

    window.__googleMapsLoadingPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(
        "script[data-google-maps-loader='true']"
      );
      if (existing) {
        existing.addEventListener("load", () => resolve());
        existing.addEventListener("error", () =>
          reject(new Error("Google Maps script load failed"))
        );
        return;
      }

      const script = document.createElement("script");
      script.dataset.googleMapsLoader = "true";
      script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker&loading=async`;
      script.async = true;
      script.defer = true;

      script.onload = () => {
        resolve();
      };

      script.onerror = () => {
        reject(new Error("Google Maps script load failed"));
      };

      document.head.appendChild(script);
    });

    return window.__googleMapsLoadingPromise;
  }

  // ---------------------------------------------------------------------------
  // Initialization logic
  // ---------------------------------------------------------------------------
  async tryInitializeAutocomplete() {
    if (this._initialized) return;

    // Si no están los targets todavía, reintentamos un poco (Turbo/accordion)
    if (!this.hasInputTarget || !this.hasMapTarget) {
      this._initAttempts += 1;
      console.warn(
        "⚠️ Missing input or map target (address-autocomplete). Attempt:",
        this._initAttempts
      );

      // reintentos suaves; si el usuario abre el accordion luego, también inicializa por listener
      if (this._initAttempts <= 10) {
        setTimeout(() => this.tryInitializeAutocomplete(), 200);
      }
      return;
    }

    try {
      const { Map } = await google.maps.importLibrary("maps");
      const { AdvancedMarkerElement } = await google.maps.importLibrary(
        "marker"
      );
      await google.maps.importLibrary("places");

      // Mapa
      this.map = new Map(this.mapTarget, {
        center: { lat: 9.9281, lng: -84.0907 },
        zoom: 13,
        mapId: "DELIVERY_ADDRESS_MAP_ID",
        mapTypeControl: false,
        streetViewControl: false,
      });

      // Marker
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

      this.geocoder = new google.maps.Geocoder();

      // Autocomplete (Places)
      this.autocomplete = new google.maps.places.Autocomplete(
        this.inputTarget,
        {
          componentRestrictions: { country: "cr" },
          fields: [
            "address_components",
            "geometry",
            "name",
            "formatted_address",
            "plus_code",
          ],
          // IMPORTANTE: no restringir tipos; CR a veces funciona mejor sin types.
          types: [],
        }
      );

      this.autocomplete.addListener("place_changed", () => {
        const place = this.autocomplete.getPlace();

        if (!place.geometry) {
          console.warn("No se encontró geometría para el lugar seleccionado");
          return;
        }

        const location = place.geometry.location;

        this.map.setCenter(location);
        this.map.setZoom(17);
        this.marker.position = location;

        this.updateCoordinates(location.lat(), location.lng());

        if (place.plus_code && this.hasPlusTarget) {
          this.plusTarget.value =
            place.plus_code.global_code || place.plus_code.compound_code || "";
        }

        this.showSelectedAddressInfo(place.formatted_address || place.name);
      });

      this._initialized = true;
      console.log("✅ Address autocomplete initialized");
    } catch (error) {
      console.error("❌ Error initializing address autocomplete:", error);
    }
  }

  // ---------------------------------------------------------------------------
  // Accordion awareness: init when section becomes visible
  // ---------------------------------------------------------------------------
  bindAccordionListener() {
    // Busca el collapse padre más cercano (Bootstrap)
    const collapseEl = this.element.closest(".accordion-collapse");
    if (!collapseEl) return;

    this._onShown = () => {
      // Cuando se abre el accordion, ya están visibles los targets
      this.tryInitializeAutocomplete();
    };

    collapseEl.addEventListener("shown.bs.collapse", this._onShown);
  }

  unbindAccordionListener() {
    const collapseEl = this.element.closest(".accordion-collapse");
    if (!collapseEl || !this._onShown) return;
    collapseEl.removeEventListener("shown.bs.collapse", this._onShown);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  updateCoordinates(lat, lng) {
    if (this.hasLatTarget) this.latTarget.value = lat.toFixed(7);
    if (this.hasLngTarget) this.lngTarget.value = lng.toFixed(7);
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

        if (this.hasInputTarget) {
          this.inputTarget.value = result.formatted_address;
          this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }));
        }

        if (result.plus_code && this.hasPlusTarget) {
          this.plusTarget.value =
            result.plus_code.global_code ||
            result.plus_code.compound_code ||
            "";
        }

        this.showSelectedAddressInfo(result.formatted_address);
      } else {
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
    let warning = document.getElementById("coordinate-warning");

    if (!warning) {
      warning = document.createElement("div");
      warning.id = "coordinate-warning";
      warning.className =
        "alert alert-warning alert-dismissible fade show mt-2";

      const detailsElement = this.element.querySelector("details");
      if (detailsElement) {
        detailsElement.appendChild(warning);
      } else {
        this.element.appendChild(warning);
      }
    }

    warning.innerHTML = `
      <strong>Advertencia:</strong> ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `;
  }
}
