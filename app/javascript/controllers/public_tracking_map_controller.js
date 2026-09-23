// app/javascript/controllers/public_tracking_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

const ETA_THROTTLE_MS = 60000; // no recalcular ruta más seguido que esto
// Camioncito (vista lateral) en círculo de marca, reemplaza la flecha de Google
const TRUCK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 44"><circle cx="22" cy="22" r="20" fill="#43322a" stroke="#fff" stroke-width="3"/><path fill="#fdf5ea" d="M10 15h14v11H10zM25 19h5l3 4v3h-8z"/><circle cx="15" cy="27" r="2.5" fill="#fdf5ea" stroke="#43322a"/><circle cx="29" cy="27" r="2.5" fill="#fdf5ea" stroke="#43322a"/></svg>`;

const POLL_INTERVAL_MS = 15000; // respaldo si el WebSocket se cae y no repone el broadcast perdido

export default class extends Controller {
  static values = {
    planId: Number,
    destLat: Number,
    destLng: Number,
    truckLat: Number,
    truckLng: Number,
    pollUrl: String,
  };
  static targets = ["map", "lastUpdate", "connectionBanner"];

  connect() {
    this.lastEtaAt = 0;
    this.initMap();
    this.subscription = subscribeToDeliveryPlan(
      this.planIdValue,
      (data) => {
        if (data.type === "position_update") {
          this.updateTruck(data.current_lat, data.current_lng, data.last_seen_at);
        }
      },
      (isConnected) => this.updateConnectionBanner(isConnected),
    );

    if (this.hasPollUrlValue) {
      this.pollTimer = setInterval(() => this.pollPosition(), POLL_INTERVAL_MS);
    }
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe();
    if (this.pollTimer) clearInterval(this.pollTimer);
  }

  async pollPosition() {
    try {
      const res = await fetch(this.pollUrlValue, { headers: { Accept: "application/json" } });
      if (!res.ok) return;
      const data = await res.json();
      if (data.current_lat && data.current_lng) {
        this.updateTruck(data.current_lat, data.current_lng, data.last_seen_at);
      }
    } catch (e) {
      console.warn("No se pudo refrescar la posición por polling:", e);
    }
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

    this.map = new google.maps.Map(this.mapTarget, {
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
        url: "data:image/svg+xml;utf8," + encodeURIComponent(TRUCK_SVG),
        scaledSize: new google.maps.Size(44, 44),
        anchor: new google.maps.Point(22, 22),
      },
    });

    // Marcador Destino
    new google.maps.Marker({
      position: destPos,
      map: this.map,
      title: "Tu ubicación",
      icon: "http://maps.google.com/mapfiles/ms/icons/red-dot.png",
    });

    this.directionsService = new google.maps.DirectionsService();
    // Dibuja el camino real por calle (pegado a la vía, como Uber/Waze) en
    // vez de solo mostrar el texto de duración/distancia. suppressMarkers
    // porque ya tenemos los pines de camión/destino propios.
    this.directionsRenderer = new google.maps.DirectionsRenderer({
      map: this.map,
      suppressMarkers: true,
      preserveViewport: true,
      polylineOptions: {
        strokeColor: "#0d6efd",
        strokeOpacity: 0.85,
        strokeWeight: 5,
      },
    });
    // Capa de tráfico en vivo de Google (congestión por color en las calles),
    // igual que Google Maps — no requiere nada más que activarla.
    this.trafficLayer = new google.maps.TrafficLayer();
    this.trafficLayer.setMap(this.map);

    this.fitBounds();
    this.updateEta();
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

    this.updateEta();
  }

  updateEta() {
    if (!this.directionsService) return;

    // La posición no cambia perceptiblemente en pocos segundos — evita
    // pegarle a la Directions API en cada position_update (cada ~15s).
    const now = Date.now();
    if (now - this.lastEtaAt < ETA_THROTTLE_MS) return;
    this.lastEtaAt = now;

    this.directionsService.route(
      {
        origin: this.truckMarker.getPosition(),
        destination: { lat: this.destLatValue, lng: this.destLngValue },
        travelMode: google.maps.TravelMode.DRIVING,
        // Con departureTime "ahora", Directions devuelve duration_in_traffic
        // usando el tráfico en vivo (las "presas") en vez de solo el tiempo
        // en calle vacía.
        drivingOptions: {
          departureTime: new Date(),
          trafficModel: google.maps.TrafficModel.BEST_GUESS,
        },
      },
      (result, status) => {
        if (status !== google.maps.DirectionsStatus.OK) return;

        this.directionsRenderer.setDirections(result);

        // Encuadra la ruta completa solo la primera vez que la calculamos —
        // en los refrescos siguientes no queremos que el mapa salte/zoom
        // mientras el cliente lo está viendo.
        if (!this.routeBoundsFitted) {
          this.map.fitBounds(result.routes[0].bounds, 50);
          this.routeBoundsFitted = true;
        }
      },
    );
  }

  updateConnectionBanner(isConnected) {
    if (!this.hasConnectionBannerTarget) return;
    this.connectionBannerTarget.hidden = isConnected;
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
