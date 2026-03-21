// app/javascript/controllers/internal_address_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "map",
    "lat",
    "lng",
    "plus",
    "addressName",
    "addressSelect",
    "description",
    "latDisplay",
    "lngDisplay",
    "plusDisplay",
    "addressDisplay",
    "statusBadge",
    "coordsStatus",
    "descStatus",
  ];

  static values = {
    apiKey: String,
  };

  connect() {
    console.log("✅ InternalAddressAutocompleteController connected");
    this._initialized = false;
    this._initAttempts = 0;

    this.loadGoogleMapsAPI().then(() => {
      this.tryInitializeAutocomplete();
    });

    // ✅ capture: true garantiza ejecución ANTES de la serialización del form
    this._submitHandler = (e) => this.ensureAddressBeforeSubmit(e);
    this.element
      .closest("form")
      ?.addEventListener("submit", this._submitHandler, { capture: true });
  }

  disconnect() {
    if (this.autocomplete)
      google.maps.event.clearInstanceListeners(this.autocomplete);
    if (this.marker) google.maps.event.clearInstanceListeners(this.marker);

    this.element
      .closest("form")
      ?.removeEventListener("submit", this._submitHandler, { capture: true });
  }

  // ===========================================================================
  // ASEGURAR ADDRESS ANTES DEL SUBMIT
  // ===========================================================================
  // En el método ensureAddressBeforeSubmit(e)
  ensureAddressBeforeSubmit(e) {
    const addressField = this.addressNameTarget;
    const descriptionField = this.descriptionTarget;

    const addressValue = addressField.value.trim();
    const descriptionValue = descriptionField.value.trim();

    // Si el mapa no puso nada pero hay descripción, copiamos la descripción al address
    if (!addressValue && descriptionValue) {
      addressField.value = descriptionValue;
      console.log("✅ Sincronizando address con description para el submit");
    }
  }

  // ===========================================================================
  // CARGA DE GOOGLE MAPS API
  // ===========================================================================
  loadGoogleMapsAPI() {
    if (window.google && window.google.maps) return Promise.resolve();
    if (window.__googleMapsLoadingPromise)
      return window.__googleMapsLoadingPromise;

    window.__googleMapsLoadingPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(
        "script[data-google-maps-loader='true']",
      );
      if (existing) {
        existing.addEventListener("load", () => resolve());
        existing.addEventListener("error", () =>
          reject(new Error("Google Maps script load failed")),
        );
        return;
      }

      const script = document.createElement("script");
      script.dataset.googleMapsLoader = "true";
      script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker,geocoding&loading=async`;
      script.async = true;
      script.defer = true;

      script.onload = () => resolve();
      script.onerror = () =>
        reject(new Error("Google Maps script load failed"));

      document.head.appendChild(script);
    });

    return window.__googleMapsLoadingPromise;
  }

  // ===========================================================================
  // INICIALIZACIÓN DEL MAPA Y AUTOCOMPLETE
  // ===========================================================================
  async tryInitializeAutocomplete() {
    if (this._initialized) return;

    if (!this.hasMapTarget) {
      this._initAttempts += 1;
      console.warn("⚠️ Missing map target. Attempt:", this._initAttempts);
      if (this._initAttempts <= 10) {
        setTimeout(() => this.tryInitializeAutocomplete(), 200);
      }
      return;
    }

    try {
      const { Map } = await google.maps.importLibrary("maps");
      const { AdvancedMarkerElement } =
        await google.maps.importLibrary("marker");
      await google.maps.importLibrary("places");
      await google.maps.importLibrary("geocoding");

      const initialLat = parseFloat(this.latTarget.value) || 9.9281;
      const initialLng = parseFloat(this.lngTarget.value) || -84.0907;

      this.map = new Map(this.mapTarget, {
        center: { lat: initialLat, lng: initialLng },
        zoom: initialLat === 9.9281 ? 13 : 17,
        mapId: "DELIVERY_ADDRESS_MAP_ID",
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: true,
      });

      this.marker = new AdvancedMarkerElement({
        map: this.map,
        position: { lat: initialLat, lng: initialLng },
        gmpDraggable: true,
        title: "Ubicación de entrega",
      });

      this.marker.addListener("dragend", (event) => {
        const position = event.latLng;
        this.updateFromCoords(position.lat(), position.lng());
        this.reverseGeocode(position);
      });

      this.map.addListener("click", (event) => {
        const position = event.latLng;
        this.marker.position = position;
        this.updateFromCoords(position.lat(), position.lng());
        this.reverseGeocode(position);
      });

      this.geocoder = new google.maps.Geocoder();

      if (this.hasInputTarget) {
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
            types: [],
          },
        );

        this.autocomplete.addListener("place_changed", () => {
          const place = this.autocomplete.getPlace();
          if (place.geometry) {
            this.updateFromPlace(place);
          }
        });
      }

      if (initialLat !== 9.9281 || initialLng !== -84.0907) {
        this.updateDisplays(initialLat, initialLng);
        this.validateStatus();
      }

      this._initialized = true;
      console.log("✅ Address autocomplete initialized");
    } catch (error) {
      console.error("❌ Error initializing address autocomplete:", error);
    }
  }

  // ===========================================================================
  // INPUT INTELIGENTE
  // ===========================================================================
  handleSmartInput(event) {
    const text = event.target.value.trim();
    if (!text) return;

    console.log("🔍 Analizando input:", text);

    const coordRegex = /^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$/;
    const coordMatch = text.match(coordRegex);
    if (coordMatch) {
      const lat = parseFloat(coordMatch[1]);
      const lng = parseFloat(coordMatch[2]);

      if (lat >= 8.0 && lat <= 11.5 && lng >= -86.0 && lng <= -82.0) {
        this.updateFromCoords(lat, lng);
        this.reverseGeocode({ lat, lng });
        event.target.value = "";
        return;
      } else {
        alert(
          `Las coordenadas ${lat}, ${lng} están fuera del rango de Costa Rica.\n\nRango válido:\nLatitud: 8.0 a 11.5\nLongitud: -86.0 a -82.0`,
        );
      }
    }

    if (text.includes("+") && text.length >= 7) {
      if (!this.geocoder) return;

      this.geocoder.geocode({ address: text }, (results, status) => {
        if (status === "OK" && results[0]) {
          this.updateFromPlace(results[0]);
          event.target.value = "";
        } else {
          alert(
            `No se pudo encontrar el Plus Code: ${text}\n\nVerifica que esté escrito correctamente.`,
          );
        }
      });
      return;
    }
  }

  // ===========================================================================
  // ACTUALIZAR DESDE COORDENADAS
  // ===========================================================================
  updateFromCoords(lat, lng) {
    const pos = { lat, lng };
    this.map.setCenter(pos);
    this.map.setZoom(17);
    this.marker.position = pos;
    this.updateFields(lat, lng);
    this.updateDisplays(lat, lng);
    this.validateStatus();
  }

  // ===========================================================================
  // ACTUALIZAR DESDE PLACE
  // ===========================================================================
  updateFromPlace(place) {
    const location = place.geometry.location;
    const lat = location.lat();
    const lng = location.lng();

    this.map.setCenter(location);
    this.map.setZoom(17);
    this.marker.position = location;
    this.updateFields(lat, lng);
    this.updateDisplays(lat, lng);

    if (place.plus_code) {
      const plusCode =
        place.plus_code.global_code || place.plus_code.compound_code || "";
      this.plusTarget.value = plusCode;
      if (this.hasPlusDisplayTarget) {
        this.plusDisplayTarget.textContent = plusCode;
      }
    }

    const address = place.formatted_address || place.name || "";
    this.addressNameTarget.value = address;
    if (this.hasAddressDisplayTarget) {
      this.addressDisplayTarget.value = address;
    }

    this.validateStatus();
  }

  // ===========================================================================
  // REVERSE GEOCODING
  // ===========================================================================
  async reverseGeocode(position) {
    if (!this.geocoder) return;

    try {
      const response = await this.geocoder.geocode({ location: position });

      if (response.results && response.results.length > 0) {
        const result = response.results[0];

        const address = result.formatted_address;
        this.addressNameTarget.value = address;
        if (this.hasAddressDisplayTarget) {
          this.addressDisplayTarget.value = address;
        }

        if (result.plus_code) {
          const plusCode =
            result.plus_code.global_code ||
            result.plus_code.compound_code ||
            "";
          this.plusTarget.value = plusCode;
          if (this.hasPlusDisplayTarget) {
            this.plusDisplayTarget.textContent = plusCode;
          }
        }
      }
    } catch (error) {
      console.error("❌ Error en reverse geocoding:", error);
    }
  }

  // ===========================================================================
  // CARGAR DIRECCIÓN EXISTENTE
  // ===========================================================================
  async loadExistingAddress(event) {
    const id = event.target.value;
    if (!id) return;

    try {
      const response = await fetch(`/delivery_addresses/${id}.json`);
      const data = await response.json();

      const lat = parseFloat(data.latitude);
      const lng = parseFloat(data.longitude);

      if (!isNaN(lat) && !isNaN(lng)) {
        this.updateFromCoords(lat, lng);

        if (this.hasDescriptionTarget && data.description) {
          this.descriptionTarget.value = data.description;
        }

        if (data.plus_code) {
          this.plusTarget.value = data.plus_code;
          if (this.hasPlusDisplayTarget) {
            this.plusDisplayTarget.textContent = data.plus_code;
          }
        }

        if (data.address) {
          this.addressNameTarget.value = data.address;
          if (this.hasAddressDisplayTarget) {
            this.addressDisplayTarget.value = data.address;
          }
        }

        this.validateStatus();
      }
    } catch (error) {
      console.error("❌ Error loading existing address:", error);
    }
  }

  // ===========================================================================
  // ACTUALIZAR CAMPOS HIDDEN
  // ===========================================================================
  updateFields(lat, lng) {
    this.latTarget.value = lat.toFixed(7);
    this.lngTarget.value = lng.toFixed(7);
  }

  // ===========================================================================
  // ACTUALIZAR DISPLAYS VISUALES
  // ===========================================================================
  updateDisplays(lat, lng) {
    if (this.hasLatDisplayTarget) {
      this.latDisplayTarget.textContent = lat.toFixed(5);
    }
    if (this.hasLngDisplayTarget) {
      this.lngDisplayTarget.textContent = lng.toFixed(5);
    }
  }

  // ===========================================================================
  // VALIDACIÓN DE ESTADO
  // ===========================================================================
  validateStatus() {
    const hasCoords =
      this.latTarget.value &&
      this.lngTarget.value &&
      parseFloat(this.latTarget.value) !== 0 &&
      parseFloat(this.lngTarget.value) !== 0;

    const hasDescription =
      this.hasDescriptionTarget &&
      this.descriptionTarget.value.trim().length >= 10;

    if (this.hasCoordsStatusTarget) {
      if (hasCoords) {
        this.coordsStatusTarget.className = "badge bg-success";
        this.coordsStatusTarget.innerHTML =
          '<i class="bi bi-check-circle me-1"></i> Coordenadas: OK';
      } else {
        this.coordsStatusTarget.className = "badge bg-warning";
        this.coordsStatusTarget.innerHTML =
          '<i class="bi bi-exclamation-circle me-1"></i> Coordenadas: Pendiente';
      }
    }

    if (this.hasDescStatusTarget) {
      if (hasDescription) {
        this.descStatusTarget.className = "badge bg-success";
        this.descStatusTarget.innerHTML =
          '<i class="bi bi-check-circle me-1"></i> Descripción: OK';
      } else {
        this.descStatusTarget.className = "badge bg-warning";
        this.descStatusTarget.innerHTML =
          '<i class="bi bi-exclamation-circle me-1"></i> Descripción: Pendiente';
      }
    }

    if (this.hasStatusBadgeTarget) {
      if (hasCoords && hasDescription) {
        this.statusBadgeTarget.className = "badge bg-success";
        this.statusBadgeTarget.textContent = "✓ Completo";
      } else {
        this.statusBadgeTarget.className = "badge bg-warning text-dark";
        this.statusBadgeTarget.textContent = "⚠ Incompleto";
      }
    }
  }
}
