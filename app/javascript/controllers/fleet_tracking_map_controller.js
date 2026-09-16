// app/javascript/controllers/fleet_tracking_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

const STALE_MINUTES = 5;
const STOPPED_MINUTES = 10;
// El celular reporta cada ~10-15s manejando. Un hueco mayor a esto entre dos
// pings consecutivos significa que se perdieron lecturas de por medio (señal,
// app en background, etc.) — la Roads API no reconstruye el camino real ahí,
// solo interpola una línea entre los dos puntos que sí logró ajustar a calle.
const ROUTE_GAP_SECONDS = 60;

export default class extends Controller {
  static targets = ["map", "list"];
  static values = { apiKey: String, plans: Array };

  connect() {
    this.trucks = new Map(); // planId -> { data, marker, subscription, row, routePolyline }
    this.subscriptions = [];
    this.initMap();
  }

  disconnect() {
    this.subscriptions.forEach((s) => s.unsubscribe());
    if (this.alertInterval) clearInterval(this.alertInterval);
  }

  async initMap() {
    await this.waitForGoogleMaps();

    this.map = new google.maps.Map(this.mapTarget, {
      center: { lat: 9.9281, lng: -84.0907 },
      zoom: 10,
      mapTypeControl: false,
      streetViewControl: false,
    });

    const bounds = new google.maps.LatLngBounds();
    let hasValidPosition = false;

    this.plansValue.forEach((plan) => {
      this.addTruck(plan);
      if (this._validCoord(plan.current_lat) && this._validCoord(plan.current_lng)) {
        bounds.extend({ lat: plan.current_lat, lng: plan.current_lng });
        hasValidPosition = true;
      }
    });

    if (hasValidPosition) this.map.fitBounds(bounds);

    this.alertInterval = setInterval(() => this.refreshAlerts(), 30000);
    this.refreshAlerts();
  }

  async waitForGoogleMaps() {
    if (window.google?.maps) return;
    if (!document.querySelector("#google-maps-script")) {
      const script = document.createElement("script");
      script.id = "google-maps-script";
      script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}`;
      script.async = true;
      document.head.appendChild(script);
    }
    return new Promise((resolve) => {
      const check = () => (window.google?.maps ? resolve() : setTimeout(check, 200));
      check();
    });
  }

  _validCoord(v) {
    return v !== 0 && v !== null && Number.isFinite(v);
  }

  addTruck(plan) {
    const row = this.buildRow(plan);
    this.listTarget.appendChild(row);

    let marker = null;
    if (this._validCoord(plan.current_lat) && this._validCoord(plan.current_lng)) {
      const position = this._dedupePosition(plan.id, plan.current_lat, plan.current_lng);
      marker = this._buildMarker(plan.id, position, plan.driver_name, plan.status);
    }

    // Un plan completado ya no recibe posiciones nuevas: suscribirse al canal
    // solo abre una conexión que jamás va a emitir nada.
    let subscription = null;
    if (plan.status !== "completed") {
      subscription = subscribeToDeliveryPlan(plan.id, (data) => {
        if (data.type !== "position_update") return;
        this.updateTruckPosition(plan.id, data);
      });
      this.subscriptions.push(subscription);
    }

    this.trucks.set(plan.id, {
      data: { ...plan },
      marker,
      row,
      routePolyline: null,
      lastMovedAt: plan.last_seen_at ? new Date(plan.last_seen_at).getTime() : null,
    });
  }

  // Dos planes con el mismo conductor/camión (ruta vieja que quedó activa,
  // o mañana + tarde el mismo día) pueden compartir casi la misma posición
  // GPS: sin esto, sus pines quedan exactamente encimados y parecen uno solo.
  // Aplica un pequeño desplazamiento en espiral por cada plan ya ubicado ahí.
  _dedupePosition(planId, lat, lng) {
    const THRESHOLD = 0.0001; // ~11m
    let collisions = 0;
    this.trucks.forEach((truck, id) => {
      if (id === planId) return;
      const { current_lat: tLat, current_lng: tLng } = truck.data;
      if (!this._validCoord(tLat) || !this._validCoord(tLng)) return;
      if (Math.abs(tLat - lat) < THRESHOLD && Math.abs(tLng - lng) < THRESHOLD) collisions++;
    });

    if (!collisions) return { lat, lng };

    const angle = (collisions * 137.5 * Math.PI) / 180; // ángulo dorado: reparte los pines sin que se vuelvan a encimar
    const radius = 0.00015 * collisions;
    return { lat: lat + radius * Math.cos(angle), lng: lng + radius * Math.sin(angle) };
  }

  buildRow(plan) {
    const row = document.createElement("li");
    row.className = "list-group-item";
    row.dataset.planId = plan.id;
    row.style.cursor = "pointer";
    const dateLabel = plan.date_label ? ` · ${this._escapeHtml(plan.date_label)}` : "";
    const completedBadge = plan.status === "completed"
      ? '<span class="badge bg-secondary ms-1">Completada</span>'
      : "";
    row.innerHTML = `
      <div class="d-flex justify-content-between align-items-start">
        <div>
          <strong>${this._escapeHtml(plan.driver_name)}</strong>${completedBadge}
          <div class="small text-muted">${this._escapeHtml(plan.truck)} — ${plan.completed_stops}/${plan.total_stops} paradas${dateLabel}</div>
          <div class="small text-muted" data-role="last-seen"></div>
        </div>
        <span class="badge" data-role="alert-badge"></span>
      </div>
      <button type="button" class="btn btn-sm btn-outline-secondary mt-2" data-role="route-toggle">
        Ver recorrido
      </button>
    `;
    row.addEventListener("click", () => this.selectTruck(plan.id));
    row.querySelector('[data-role="route-toggle"]').addEventListener("click", (e) => {
      e.stopPropagation();
      this.toggleRoute(plan.id);
    });
    return row;
  }

  _buildMarker(planId, position, title, status) {
    const completed = status === "completed";
    const marker = new google.maps.Marker({
      position,
      map: this.map,
      icon: {
        path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
        scale: 6,
        fillColor: completed ? "#6c757d" : "#0d6efd",
        fillOpacity: completed ? 0.7 : 1,
        strokeColor: "#ffffff",
        strokeWeight: 2,
      },
      title,
    });
    marker.addListener("click", () => this.selectTruck(planId));
    return marker;
  }

  selectTruck(planId) {
    const truck = this.trucks.get(planId);
    if (!truck) return;

    if (this.selectedRow) this.selectedRow.classList.remove("active");
    truck.row.classList.add("active");
    this.selectedRow = truck.row;

    if (truck.marker) this.map.panTo(truck.marker.getPosition());
  }

  _escapeHtml(str) {
    return String(str ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  updateTruckPosition(planId, { current_lat, current_lng, last_seen_at, recorded_by_name }) {
    const truck = this.trucks.get(planId);
    if (!truck) return;

    const lat = parseFloat(current_lat);
    const lng = parseFloat(current_lng);
    if (!this._validCoord(lat) || !this._validCoord(lng)) return;

    // "Detenido" mide si la posición cambió, no solo si llegó un mensaje —
    // el driver puede seguir enviando batches idénticos mientras espera en una parada.
    const moved = truck.data.current_lat !== lat || truck.data.current_lng !== lng;
    if (moved || !truck.lastMovedAt) truck.lastMovedAt = Date.now();

    truck.data.current_lat = lat;
    truck.data.current_lng = lng;
    truck.data.last_seen_at = last_seen_at;
    truck.data.recorded_by_name = recorded_by_name;

    const position = this._dedupePosition(planId, lat, lng);
    if (truck.marker) {
      truck.marker.setPosition(position);
    } else {
      truck.marker = this._buildMarker(planId, position, truck.data.driver_name, truck.data.status);
    }

    this.refreshAlerts();
  }

  refreshAlerts() {
    const now = Date.now();

    this.trucks.forEach((truck) => {
      const lastSeenEl = truck.row.querySelector('[data-role="last-seen"]');
      const badgeEl = truck.row.querySelector('[data-role="alert-badge"]');

      if (truck.data.status === "completed") {
        lastSeenEl.textContent = truck.data.last_seen_at
          ? `Última posición: ${new Date(truck.data.last_seen_at).toLocaleString()}`
          : "Sin datos GPS";
        badgeEl.textContent = "";
        badgeEl.className = "badge";
        return;
      }

      if (!truck.data.last_seen_at) {
        lastSeenEl.textContent = "Sin datos GPS";
        badgeEl.textContent = "";
        return;
      }

      const minutesSinceSeen = (now - new Date(truck.data.last_seen_at).getTime()) / 60000;
      lastSeenEl.textContent = `Última actualización: hace ${Math.max(0, Math.round(minutesSinceSeen))} min`;

      const minutesSinceMoved = truck.lastMovedAt ? (now - truck.lastMovedAt) / 60000 : minutesSinceSeen;

      if (minutesSinceSeen > STALE_MINUTES) {
        badgeEl.textContent = "GPS perdido";
        badgeEl.className = "badge bg-danger";
      } else if (minutesSinceMoved > STOPPED_MINUTES) {
        badgeEl.textContent = "Detenido";
        badgeEl.className = "badge bg-warning text-dark";
      } else {
        badgeEl.textContent = "";
        badgeEl.className = "badge";
      }
    });
  }

  async toggleRoute(planId) {
    const truck = this.trucks.get(planId);
    if (!truck) return;

    if (truck.routePolyline) {
      truck.routePolyline.setMap(null);
      truck.routePolyline = null;
      return;
    }

    const response = await fetch(`/tracking/${planId}/route`);
    if (!response.ok) return;
    const points = await response.json();
    if (!points.length) return;

    // Los puntos crudos del GPS (cada ~10-15s) no coinciden con la calle:
    // conectarlos con líneas rectas corta por patios/manzanas. La Roads API
    // los "pega" a la vía real. Si falla (API no habilitada, sin cuota, sin
    // red) se cae de vuelta a la línea recta en vez de dejar el mapa en blanco.
    const path = await this.buildRoadPath(points).catch((err) => {
      console.warn("No se pudo pegar la ruta a la calle, usando línea recta:", err);
      return points.map((p) => ({ lat: p.lat, lng: p.lng }));
    });

    truck.routePolyline = new google.maps.Polyline({
      path,
      geodesic: true,
      strokeColor: "#6f42c1",
      strokeOpacity: 0.8,
      strokeWeight: 3,
      map: this.map,
    });

    const bounds = new google.maps.LatLngBounds();
    path.forEach((p) => bounds.extend(p));
    this.map.fitBounds(bounds);
  }

  // Parte el recorrido crudo en tramos continuos (un hueco de más de
  // ROUTE_GAP_SECONDS entre dos pings corta el tramo). Cada tramo se ajusta
  // a la calle con la Roads API (funciona bien con GPS denso y continuo);
  // entre un tramo y el siguiente, calcula el camino real con la Directions
  // API — la misma que ya usa la pestaña "Mapa de ruta" entre paradas — en
  // vez de dejar que la Roads API interpole una línea derecha sobre el hueco.
  async buildRoadPath(points) {
    const segments = [[points[0]]];
    for (let i = 1; i < points.length; i++) {
      const gapSeconds = (new Date(points[i].captured_at) - new Date(points[i - 1].captured_at)) / 1000;
      if (gapSeconds > ROUTE_GAP_SECONDS) segments.push([]);
      segments[segments.length - 1].push(points[i]);
    }

    let path = [];
    for (let s = 0; s < segments.length; s++) {
      const snapped = await this.snapToRoads(segments[s]);
      if (s > 0 && path.length && snapped.length) {
        const bridge = await this.routeBetween(path[path.length - 1], snapped[0]);
        path = path.concat(bridge);
      }
      path = path.concat(snapped);
    }
    return path;
  }

  // Camino real entre dos puntos vía Directions API. Si falla (sin ruta
  // posible, cuota, red) conecta con línea recta solo ESE tramo puntual, en
  // vez de perder todo el recorrido.
  async routeBetween(origin, destination) {
    if (!this.directionsService) this.directionsService = new google.maps.DirectionsService();
    try {
      const result = await this.directionsService.route({
        origin,
        destination,
        travelMode: google.maps.TravelMode.DRIVING,
      });
      return result.routes[0].overview_path.map((p) => ({ lat: p.lat(), lng: p.lng() }));
    } catch (err) {
      console.warn("No se pudo calcular el tramo con Directions API, uniendo con línea recta:", err);
      return [origin, destination];
    }
  }

  // La Roads API acepta un máximo de 100 puntos por request, así que un
  // recorrido largo (varias horas de GPS) hay que partirlo en lotes
  // secuenciales y unir los tramos snapeados en orden.
  async snapToRoads(points) {
    if (points.length === 0) return [];
    if (points.length === 1) return [{ lat: points[0].lat, lng: points[0].lng }];

    const BATCH_SIZE = 100;
    const snapped = [];

    for (let i = 0; i < points.length; i += BATCH_SIZE) {
      const batch = points.slice(i, i + BATCH_SIZE);
      const path = batch.map((p) => `${p.lat},${p.lng}`).join("|");
      const url = `https://roads.googleapis.com/v1/snapToRoads?path=${path}&interpolate=true&key=${this.apiKeyValue}`;

      const response = await fetch(url);
      if (!response.ok) throw new Error(`Roads API respondió ${response.status}`);
      const data = await response.json();
      if (data.error) throw new Error(data.error.message || "Roads API error");

      (data.snappedPoints || []).forEach((sp) => {
        snapped.push({ lat: sp.location.latitude, lng: sp.location.longitude });
      });
    }

    return snapped;
  }
}
