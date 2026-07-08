import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    latitude: Number,
    longitude: Number,
  };

  connect() {
    console.log("AddressMapController connected");
    this.loadGoogleMapsAPI();
  }

  loadGoogleMapsAPI() {
    if (window.google && window.google.maps) {
      this.initializeMap();
      return;
    }

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.getApiKey()}&libraries=marker&callback=initAddressMap`;
    script.async = true;
    script.defer = true;

    window.initAddressMap = () => {
      this.initializeMap();
    };

    document.head.appendChild(script);
  }

  getApiKey() {
    // Intentar obtener la API key del controller de autocomplete
    const autocompleteController = document.querySelector(
      "[data-controller='address-autocomplete']"
    );
    if (autocompleteController) {
      return autocompleteController.dataset.addressAutocompleteApiKeyValue;
    }
    return "";
  }

  async initializeMap() {
    // El script se marca como "cargado" antes de que importLibrary quede
    // realmente disponible (setup interno asíncrono de la API); reintentar
    // evita perder la inicialización del mapa por esa carrera.
    if (typeof google?.maps?.importLibrary !== "function") {
      this._libAttempts = (this._libAttempts || 0) + 1;
      if (this._libAttempts <= 25) {
        setTimeout(() => this.initializeMap(), 200);
      }
      return;
    }

    const lat = this.latitudeValue || 9.9281;
    const lng = this.longitudeValue || -84.0907;

    const { Map } = await google.maps.importLibrary("maps");
    const { AdvancedMarkerElement } = await google.maps.importLibrary("marker");

    this.map = new Map(this.element, {
      center: { lat, lng },
      zoom: 15,
      mapId: "DEMO_MAP_ID", // Requerido para AdvancedMarkerElement
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: true,
    });

    this.marker = new AdvancedMarkerElement({
      map: this.map,
      position: { lat, lng },
      title: "Ubicación de entrega",
    });
  }

  updateMap(lat, lng) {
    if (!this.map || !this.marker) return;

    const position = { lat: parseFloat(lat), lng: parseFloat(lng) };

    this.map.setCenter(position);
    this.map.setZoom(17);
    this.marker.position = position;
  }
}
