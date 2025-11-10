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
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=places,marker&callback=initGoogleMapsAutocomplete`;
    script.async = true;
    script.defer = true;

    window.initGoogleMapsAutocomplete = () => {
      this.initializeAutocomplete();
    };

    document.head.appendChild(script);
  }

  async initializeAutocomplete() {
    if (!this.hasInputTarget || !this.hasMapTarget) return;

    // Inicializar mapa
    const { Map } = await google.maps.importLibrary("maps");
    const { AdvancedMarkerElement } = await google.maps.importLibrary("marker");

    this.map = new Map(this.mapTarget, {
      center: { lat: 9.9281, lng: -84.0907 }, // San José, Costa Rica
      zoom: 13,
      mapId: "DEMO_MAP_ID", // Requerido para AdvancedMarkerElement
      mapTypeControl: false,
      streetViewControl: false,
    });

    this.marker = new AdvancedMarkerElement({
      map: this.map,
      position: { lat: 9.9281, lng: -84.0907 },
      gmpDraggable: true,
    });

    // Listener para cuando se arrastra el marcador
    this.marker.addListener("dragend", (event) => {
      const position = event.latLng;
      this.updateCoordinates(position.lat(), position.lng());
      this.reverseGeocode(position);
    });

    // Autocomplete
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

      // Plus Code
      if (place.plus_code && this.hasPlusTarget) {
        this.plusTarget.value =
          place.plus_code.global_code || place.plus_code.compound_code || "";
      }

      // Mostrar info
      if (
        this.hasSelectedAddressInfoTarget &&
        this.hasSelectedAddressTextTarget
      ) {
        this.selectedAddressTextTarget.textContent =
          place.formatted_address || place.name;
        this.selectedAddressInfoTarget.style.display = "block";
      }
    });
  }

  updateCoordinates(lat, lng) {
    if (this.hasLatTarget) this.latTarget.value = lat;
    if (this.hasLngTarget) this.lngTarget.value = lng;
  }

  updateMapFromCoordinates(event) {
    const lat = parseFloat(this.latTarget.value);
    const lng = parseFloat(this.lngTarget.value);

    if (isNaN(lat) || isNaN(lng)) return;

    const position = { lat, lng };
    this.map.setCenter(position);
    this.map.setZoom(17);
    this.marker.position = position;
  }

  reverseGeocode(position) {
    const geocoder = new google.maps.Geocoder();

    geocoder.geocode({ location: position }, (results, status) => {
      if (status === "OK" && results[0]) {
        this.inputTarget.value = results[0].formatted_address;

        if (results[0].plus_code && this.hasPlusTarget) {
          this.plusTarget.value = results[0].plus_code.global_code || "";
        }
      }
    });
  }
}
