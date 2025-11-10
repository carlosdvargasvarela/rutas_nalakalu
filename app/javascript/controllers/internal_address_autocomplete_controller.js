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
