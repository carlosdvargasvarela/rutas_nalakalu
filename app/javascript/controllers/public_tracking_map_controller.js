// app/javascript/controllers/public_tracking_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

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
    // Validar coordenadas antes de inicializar
    if (!this.hasValidCoordinates(this.truckLatValue, this.truckLngValue)) {
      console.warn(
        "Coordenadas del camión inválidas, usando coordenadas por defecto",
      );
      this.truckLatValue = this.destLatValue || 9.9281; // San José, Costa Rica
      this.truckLngValue = this.destLngValue || -84.0907;
    }

    if (!this.hasValidCoordinates(this.destLatValue, this.destLngValue)) {
      console.warn(
        "Coordenadas de destino inválidas, usando coordenadas del camión",
      );
      this.destLatValue = this.truckLatValue;
      this.destLngValue = this.truckLngValue;
    }

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
    // Validar coordenadas antes de actualizar
    if (!this.hasValidCoordinates(lat, lng)) {
      console.warn("Coordenadas inválidas recibidas:", lat, lng);
      return;
    }

    const pos = { lat: parseFloat(lat), lng: parseFloat(lng) };
    this.truckMarker.setPosition(pos);

    if (this.lastUpdateTarget) {
      this.lastUpdateTarget.textContent = "Actualizado hace un momento";
    }
  }

  fitBounds() {
    const bounds = new google.maps.LatLngBounds();
    bounds.extend({ lat: this.truckLatValue, lng: this.truckLngValue });
    bounds.extend({ lat: this.destLatValue, lng: this.destLngValue });
    this.map.fitBounds(bounds, 50);
  }

  hasValidCoordinates(lat, lng) {
    return (
      lat !== null &&
      lng !== null &&
      !isNaN(lat) &&
      !isNaN(lng) &&
      isFinite(lat) &&
      isFinite(lng) &&
      lat !== 0 &&
      lng !== 0
    );
  }
}
