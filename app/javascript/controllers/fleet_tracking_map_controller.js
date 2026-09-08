// app/javascript/controllers/fleet_tracking_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

const STALE_MINUTES = 5;
const STOPPED_MINUTES = 10;

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
      marker = this._buildMarker(plan.id, { lat: plan.current_lat, lng: plan.current_lng }, plan.driver_name);
    }

    const subscription = subscribeToDeliveryPlan(plan.id, (data) => {
      if (data.type !== "position_update") return;
      this.updateTruckPosition(plan.id, data);
    });
    this.subscriptions.push(subscription);

    this.trucks.set(plan.id, {
      data: { ...plan },
      marker,
      row,
      routePolyline: null,
      lastMovedAt: plan.last_seen_at ? new Date(plan.last_seen_at).getTime() : null,
    });
  }

  buildRow(plan) {
    const row = document.createElement("li");
    row.className = "list-group-item";
    row.dataset.planId = plan.id;
    row.style.cursor = "pointer";
    row.innerHTML = `
      <div class="d-flex justify-content-between align-items-start">
        <div>
          <strong>${this._escapeHtml(plan.driver_name)}</strong>
          <div class="small text-muted">${this._escapeHtml(plan.truck)} — ${plan.completed_stops}/${plan.total_stops} paradas</div>
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

  _buildMarker(planId, position, title) {
    const marker = new google.maps.Marker({
      position,
      map: this.map,
      icon: {
        path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
        scale: 6,
        fillColor: "#0d6efd",
        fillOpacity: 1,
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
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

    // "Detenido" mide si la posición cambió, no solo si llegó un mensaje —
    // el driver puede seguir enviando batches idénticos mientras espera en una parada.
    const moved = truck.data.current_lat !== lat || truck.data.current_lng !== lng;
    if (moved || !truck.lastMovedAt) truck.lastMovedAt = Date.now();

    truck.data.current_lat = lat;
    truck.data.current_lng = lng;
    truck.data.last_seen_at = last_seen_at;
    truck.data.recorded_by_name = recorded_by_name;

    const position = { lat, lng };
    if (truck.marker) {
      truck.marker.setPosition(position);
    } else {
      truck.marker = this._buildMarker(planId, position, truck.data.driver_name);
    }

    this.refreshAlerts();
  }

  refreshAlerts() {
    const now = Date.now();

    this.trucks.forEach((truck) => {
      const lastSeenEl = truck.row.querySelector('[data-role="last-seen"]');
      const badgeEl = truck.row.querySelector('[data-role="alert-badge"]');

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

    truck.routePolyline = new google.maps.Polyline({
      path: points.map((p) => ({ lat: p.lat, lng: p.lng })),
      geodesic: true,
      strokeColor: "#6f42c1",
      strokeOpacity: 0.8,
      strokeWeight: 3,
      map: this.map,
    });

    const bounds = new google.maps.LatLngBounds();
    points.forEach((p) => bounds.extend({ lat: p.lat, lng: p.lng }));
    this.map.fitBounds(bounds);
  }
}
