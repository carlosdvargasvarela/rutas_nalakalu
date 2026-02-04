// app/javascript/controllers/admin_driver_map_controller.js
import { Controller } from "@hotwired/stimulus";
import { subscribeToDeliveryPlan } from "channels/delivery_plan_channel";

export default class extends Controller {
  static values = {
    deliveryPlanId: Number,
    currentLat: Number,
    currentLng: Number,
    assignments: Array,
  };

  connect() {
    console.log("🗺️ Admin Driver Map conectado");
    console.log("📍 Delivery Plan ID:", this.deliveryPlanIdValue);
    console.log("📍 Current Lat:", this.currentLatValue);
    console.log("📍 Current Lng:", this.currentLngValue);
    console.log("📍 Assignments:", this.assignmentsValue);

    if (!this.deliveryPlanIdValue || isNaN(this.deliveryPlanIdValue)) {
      console.error("❌ ID inválido");
      return;
    }

    this.subscription = subscribeToDeliveryPlan(
      this.deliveryPlanIdValue,
      (data) => {
        if (data.type === "position_update") {
          this.updateDriverPosition(data.current_lat, data.current_lng);
          this.updateLastSeenTime(data.last_seen_at);
        }
      },
    );

    this.initMap();
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
  }

  async initMap() {
    await this.waitForGoogleMaps();

    // ✅ Usar valores por defecto si no hay coordenadas
    const defaultLat = this.hasCurrentLatValue ? this.currentLatValue : 9.9281;
    const defaultLng = this.hasCurrentLngValue
      ? this.currentLngValue
      : -84.0907;

    console.log("🗺️ Inicializando mapa en:", defaultLat, defaultLng);

    // Crear mapa
    this.map = new google.maps.Map(this.element, {
      center: { lat: defaultLat, lng: defaultLng },
      zoom: 12,
      mapTypeControl: true,
      streetViewControl: false,
      fullscreenControl: true,
    });

    // Marcador del conductor (camión)
    this.driverMarker = new google.maps.Marker({
      position: { lat: defaultLat, lng: defaultLng },
      map: this.map,
      icon: {
        path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
        scale: 7,
        fillColor: "#0d6efd",
        fillOpacity: 1,
        strokeColor: "#ffffff",
        strokeWeight: 2,
        rotation: 0,
      },
      title: "Posición del conductor",
      zIndex: 1000,
    });

    // Info window para el conductor
    this.driverInfoWindow = new google.maps.InfoWindow({
      content: `
        <div style="padding: 10px;">
          <strong>🚚 Conductor</strong><br>
          <small>Última actualización: <span id="driver-last-seen">Cargando...</span></small>
        </div>
      `,
    });

    this.driverMarker.addListener("click", () => {
      this.driverInfoWindow.open(this.map, this.driverMarker);
    });

    // Marcadores de entregas
    this.deliveryMarkers = [];
    this.createDeliveryMarkers();

    // Dibujar ruta
    this.drawRoute();
  }

  createDeliveryMarkers() {
    if (!this.assignmentsValue || this.assignmentsValue.length === 0) {
      console.warn("⚠️ No hay assignments para mostrar");
      return;
    }

    this.assignmentsValue.forEach((assignment) => {
      const delivery = assignment.delivery;

      if (!delivery.latitude || !delivery.longitude) {
        console.warn(`⚠️ Parada #${assignment.stop_order} sin coordenadas`);
        return;
      }

      const lat = parseFloat(delivery.latitude);
      const lng = parseFloat(delivery.longitude);

      if (isNaN(lat) || isNaN(lng)) {
        console.warn(
          `⚠️ Parada #${assignment.stop_order} con coordenadas inválidas:`,
          lat,
          lng,
        );
        return;
      }

      const position = { lat, lng };

      const marker = new google.maps.Marker({
        position: position,
        map: this.map,
        label: {
          text: assignment.stop_order.toString(),
          color: "#ffffff",
          fontWeight: "bold",
          fontSize: "14px",
        },
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 14,
          fillColor: this.getMarkerColor(assignment.status),
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2,
        },
        title: delivery.customer.name,
        zIndex: 100 + assignment.stop_order,
      });

      const infoWindow = new google.maps.InfoWindow({
        content: `
          <div style="padding: 8px; min-width: 200px;">
            <strong>Parada #${assignment.stop_order}</strong><br>
            <strong>${delivery.customer.name}</strong><br>
            <small class="text-muted">${delivery.customer.address || "Sin dirección"}</small><br>
            <span class="badge bg-${this.getStatusBadge(assignment.status)} mt-2">
              ${this.getStatusLabel(assignment.status)}
            </span>
          </div>
        `,
      });

      marker.addListener("click", () => {
        infoWindow.open(this.map, marker);
      });

      this.deliveryMarkers.push({ marker, assignment });
    });

    console.log(`✅ ${this.deliveryMarkers.length} marcadores creados`);
  }

  drawRoute() {
    const routePoints = [];
    const bounds = new google.maps.LatLngBounds();

    // Posición actual del conductor
    if (this.hasCurrentLatValue && this.hasCurrentLngValue) {
      const driverPos = {
        lat: this.currentLatValue,
        lng: this.currentLngValue,
      };
      routePoints.push(driverPos);
      bounds.extend(driverPos);
    }

    // Entregas pendientes en orden
    this.assignmentsValue
      .filter((a) => a.status === "pending" || a.status === "in_route")
      .sort((a, b) => a.stop_order - b.stop_order)
      .forEach((assignment) => {
        const delivery = assignment.delivery;
        if (delivery.latitude && delivery.longitude) {
          const lat = parseFloat(delivery.latitude);
          const lng = parseFloat(delivery.longitude);

          if (!isNaN(lat) && !isNaN(lng)) {
            const pos = { lat, lng };
            routePoints.push(pos);
            bounds.extend(pos);
          }
        }
      });

    // Crear polyline
    if (this.routeLine) {
      this.routeLine.setMap(null);
    }

    if (routePoints.length > 0) {
      this.routeLine = new google.maps.Polyline({
        path: routePoints,
        geodesic: true,
        strokeColor: "#0d6efd",
        strokeOpacity: 0.7,
        strokeWeight: 4,
        map: this.map,
      });

      // Ajustar vista
      this.map.fitBounds(bounds, { padding: 80 });
    }
  }

  getMarkerColor(status) {
    const colors = {
      pending: "#6c757d",
      in_route: "#ffc107",
      completed: "#198754",
      cancelled: "#dc3545",
    };
    return colors[status] || "#6c757d";
  }

  getStatusBadge(status) {
    const badges = {
      pending: "secondary",
      in_route: "warning",
      completed: "success",
      cancelled: "danger",
    };
    return badges[status] || "secondary";
  }

  getStatusLabel(status) {
    const labels = {
      pending: "Pendiente",
      in_route: "En ruta",
      completed: "Completada",
      cancelled: "Fallida",
    };
    return labels[status] || status;
  }

  updateDriverPosition(lat, lng) {
    const latNum = parseFloat(lat);
    const lngNum = parseFloat(lng);

    // 🛑 Blindaje total contra GPS inválido
    if (
      Number.isNaN(latNum) ||
      Number.isNaN(lngNum) ||
      !Number.isFinite(latNum) ||
      !Number.isFinite(lngNum)
    ) {
      console.warn("⚠️ Coordenadas inválidas ignoradas:", lat, lng);
      return;
    }

    this.currentLatValue = latNum;
    this.currentLngValue = lngNum;

    const newPosition = { lat: latNum, lng: lngNum };

    this.driverMarker.setPosition(newPosition);
    this.map.panTo(newPosition);

    this.drawRoute();
  }

  updateLastSeenTime(timestamp) {
    if (!timestamp) return;

    const date = new Date(timestamp);
    const now = new Date();
    const diffSeconds = Math.floor((now - date) / 1000);

    let timeText;
    if (diffSeconds < 60) {
      timeText = "Hace unos segundos";
    } else if (diffSeconds < 3600) {
      timeText = `Hace ${Math.floor(diffSeconds / 60)} minutos`;
    } else {
      timeText = date.toLocaleTimeString("es-CR");
    }

    const element = document.getElementById("driver-last-seen");
    if (element) {
      element.textContent = timeText;
    }

    const adminUpdate = document.getElementById("admin-last-update");
    if (adminUpdate) {
      adminUpdate.textContent = timeText;
    }
  }

  updateAssignmentStatuses(assignments) {
    let statusChanged = false;

    assignments.forEach((assignment) => {
      const markerData = this.deliveryMarkers.find(
        (m) => m.assignment.id === assignment.id,
      );

      if (markerData && markerData.assignment.status !== assignment.status) {
        statusChanged = true;
        markerData.assignment.status = assignment.status;

        // Actualizar color del marker
        markerData.marker.setIcon({
          path: google.maps.SymbolPath.CIRCLE,
          scale: 14,
          fillColor: this.getMarkerColor(assignment.status),
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2,
        });
      }
    });

    // Redibujar ruta si cambió algún estado
    if (statusChanged) {
      this.drawRoute();
    }
  }

  async waitForGoogleMaps() {
    return new Promise((resolve) => {
      if (window.google && window.google.maps) {
        resolve();
      } else {
        const checkInterval = setInterval(() => {
          if (window.google && window.google.maps) {
            clearInterval(checkInterval);
            resolve();
          }
        }, 100);
      }
    });
  }
}
