import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "../channels/delivery_plan_channel";

export default class extends Controller {
  static values = {
    planId: Number,
    destLat: Number,
    destLng: Number,
    truckLat: Number,
    truckLng: Number,
  };
  static targets = ["lastUpdate"];

  connect() {
    this.initMap();
    this.subscription = subscribeToDeliveryPlan(this.planIdValue, (data) => {
      if (data.type === "position_update") {
        this.updateTruck(data.current_lat, data.current_lng, data.last_seen_at);
      }
    });
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe();
  }

  initMap() {
    const truckPos = { lat: this.truckLatValue, lng: this.truckLngValue };
    const destPos = { lat: this.destLatValue, lng: this.destLngValue };

    this.map = new google.maps.Map(this.element, {
      center: truckPos,
      zoom: 14,
      disableDefaultUI: true,
      zoomControl: true,
    });

    // Marcador Camión
    this.truckMarker = new google.maps.Marker({
      position: truckPos,
      map: this.map,
      icon: {
        path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
        scale: 6,
        fillColor: "#0d6efd",
        fillOpacity: 1,
        strokeColor: "#fff",
        strokeWeight: 2,
      },
    });

    // Marcador Destino
    new google.maps.Marker({
      position: destPos,
      map: this.map,
      title: "Tu ubicación",
      icon: "http://maps.google.com/mapfiles/ms/icons/red-dot.png",
    });

    this.fitBounds();
  }

  updateTruck(lat, lng, timestamp) {
    const pos = { lat: parseFloat(lat), lng: parseFloat(lng) };
    this.truckMarker.setPosition(pos);
    if (this.lastUpdateTarget)
      this.lastUpdateTarget.textContent = "Actualizado hace un momento";
  }

  fitBounds() {
    const bounds = new google.maps.LatLngBounds();
    bounds.extend({ lat: this.truckLatValue, lng: this.truckLngValue });
    bounds.extend({ lat: this.destLatValue, lng: this.destLngValue });
    this.map.fitBounds(bounds, 50);
  }
}
