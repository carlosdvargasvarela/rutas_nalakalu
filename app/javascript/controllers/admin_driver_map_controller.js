// app/javascript/controllers/admin_driver_map_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    deliveryPlanId: Number,
    currentLat: Number,
    currentLng: Number,
    assignments: Array,
  };

  connect() {
    this.initMap();
    this.startPolling();

    // 🔁 Refrescar cuando se marque una entrega como fallida/completada
    window.addEventListener("assignment:updated", this.handleAssignmentUpdated);
  }

  disconnect() {
    window.removeEventListener(
      "assignment:updated",
      this.handleAssignmentUpdated
    );
    this.stopPolling();
  }

  handleAssignmentUpdated = (event) => {
    const { assignment } = event.detail;
    console.log("♻️ Cambio recibido en mapa Admin:", assignment);
    this.updateAssignmentStatuses([assignment]);
  };

  async initMap() {
    // Esperar a que Google Maps esté cargado
    await this.waitForGoogleMaps();

    const defaultLat = this.currentLatValue || 9.9281;
    const defaultLng = this.currentLngValue || -84.0907;

    // Crear mapa
    this.map = new google.maps.Map(this.element, {
      center: { lat: defaultLat, lng: defaultLng },
      zoom: 13,
      mapTypeControl: true,
      streetViewControl: false,
      fullscreenControl: true,
    });

    // 🆕 Inicializar Directions Service y Renderer
    this.directionsService = new google.maps.DirectionsService();
    this.directionsRenderer = new google.maps.DirectionsRenderer({
      map: this.map,
      suppressMarkers: true, // Usamos nuestros propios markers
      polylineOptions: {
        strokeColor: "#0d6efd",
        strokeOpacity: 0.7,
        strokeWeight: 4,
      },
      preserveViewport: true, // No cambiar el zoom automáticamente
    });

    // Marcador del conductor (camión)
    this.driverMarker = new google.maps.Marker({
      position: { lat: defaultLat, lng: defaultLng },
      map: this.map,
      icon: {
        path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
        scale: 6,
        fillColor: "#0d6efd",
        fillOpacity: 1,
        strokeColor: "#ffffff",
        strokeWeight: 2,
        rotation: 0,
      },
      title: "Conductor",
      zIndex: 1000, // Asegurar que esté encima de todo
    });

    // Info window para el conductor
    this.driverInfoWindow = new google.maps.InfoWindow({
      content: this.getDriverInfoContent(),
    });

    this.driverMarker.addListener("click", () => {
      this.driverInfoWindow.open(this.map, this.driverMarker);
    });

    // Marcadores de entregas
    this.deliveryMarkers = [];
    this.assignmentsValue.forEach((assignment, index) => {
      const delivery = assignment.delivery;
      if (delivery.latitude && delivery.longitude) {
        this.createDeliveryMarker(assignment, index + 1);
      }
    });

    // 🆕 Calcular y dibujar ruta con Directions API
    this.updateRouteWithDirections();
  }

  createDeliveryMarker(assignment, stopNumber) {
    const delivery = assignment.delivery;
    const position = {
      lat: parseFloat(delivery.latitude),
      lng: parseFloat(delivery.longitude),
    };

    const marker = new google.maps.Marker({
      position: position,
      map: this.map,
      label: {
        text: stopNumber.toString(),
        color: "#ffffff",
        fontWeight: "bold",
      },
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 12,
        fillColor: this.getMarkerColor(assignment.status),
        fillOpacity: 1,
        strokeColor: "#ffffff",
        strokeWeight: 2,
      },
      title: delivery.customer.name,
      zIndex: 100 + stopNumber,
    });

    const infoWindow = new google.maps.InfoWindow({
      content: `
        <div style="padding: 8px;">
          <strong>Parada ${stopNumber}</strong><br>
          ${delivery.customer.name}<br>
          <span class="badge bg-${this.getStatusBadge(assignment.status)}">${
        assignment.status
      }</span>
        </div>
      `,
    });

    marker.addListener("click", () => {
      infoWindow.open(this.map, marker);
    });

    this.deliveryMarkers.push({ marker, assignment, stopNumber });
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

  getDriverInfoContent() {
    return `
      <div style="padding: 8px;">
        <strong>🚚 Conductor</strong><br>
        <small>Última actualización: <span id="driver-last-seen">--</span></small>
      </div>
    `;
  }

  // 🆕 Método principal para calcular ruta con Directions API
  updateRouteWithDirections() {
    // Obtener solo las paradas pendientes o en ruta
    const pendingStops = this.assignmentsValue
      .filter((a) => a.status === "pending" || a.status === "in_route")
      .sort((a, b) => a.stop_order - b.stop_order);

    if (pendingStops.length === 0) {
      // No hay paradas pendientes, limpiar ruta
      this.directionsRenderer.setDirections({ routes: [] });
      return;
    }

    // Origen: posición actual del conductor o primera parada
    let origin;
    if (this.currentLatValue && this.currentLngValue) {
      origin = { lat: this.currentLatValue, lng: this.currentLngValue };
    } else {
      const firstStop = pendingStops[0].delivery;
      origin = {
        lat: parseFloat(firstStop.latitude),
        lng: parseFloat(firstStop.longitude),
      };
    }

    // Destino: última parada pendiente
    const lastStop = pendingStops[pendingStops.length - 1].delivery;
    const destination = {
      lat: parseFloat(lastStop.latitude),
      lng: parseFloat(lastStop.longitude),
    };

    // Waypoints: paradas intermedias
    const waypoints = pendingStops.slice(0, -1).map((assignment) => ({
      location: {
        lat: parseFloat(assignment.delivery.latitude),
        lng: parseFloat(assignment.delivery.longitude),
      },
      stopover: true,
    }));

    // Si el conductor está en movimiento, agregar su posición como primer waypoint
    if (
      this.currentLatValue &&
      this.currentLngValue &&
      pendingStops.length > 0
    ) {
      const firstStopPos = {
        lat: parseFloat(pendingStops[0].delivery.latitude),
        lng: parseFloat(pendingStops[0].delivery.longitude),
      };

      // Solo si el conductor no está en la primera parada
      const distance = this.calculateDistance(origin, firstStopPos);
      if (distance > 0.05) {
        // Más de 50 metros
        // El origen ya es la posición del conductor
        // Los waypoints incluyen todas las paradas menos la última
      }
    }

    // Limitar a 25 waypoints (límite de Google)
    const limitedWaypoints = waypoints.slice(0, 25);

    const request = {
      origin,
      destination,
      waypoints: limitedWaypoints,
      travelMode: google.maps.TravelMode.DRIVING,
      region: "CR",
      optimizeWaypoints: false, // Mantener el orden de las paradas
    };

    this.directionsService.route(request, (result, status) => {
      if (status === google.maps.DirectionsStatus.OK) {
        this.directionsRenderer.setDirections(result);

        // Ajustar vista para mostrar toda la ruta
        const bounds = new google.maps.LatLngBounds();
        result.routes[0].legs.forEach((leg) => {
          bounds.extend(leg.start_location);
          bounds.extend(leg.end_location);
        });
        this.map.fitBounds(bounds, { padding: 50 });
      } else {
        console.warn("No se pudo calcular la ruta:", status);
        // Fallback: línea simple
        this.drawSimpleRouteLine();
      }
    });
  }

  // 🆕 Fallback: dibujar línea simple si falla Directions API
  drawSimpleRouteLine() {
    const routePoints = [];
    const bounds = new google.maps.LatLngBounds();

    // Posición actual del conductor
    if (this.currentLatValue && this.currentLngValue) {
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
          const pos = {
            lat: parseFloat(delivery.latitude),
            lng: parseFloat(delivery.longitude),
          };
          routePoints.push(pos);
          bounds.extend(pos);
        }
      });

    // Crear polyline simple
    if (!this.fallbackPolyline) {
      this.fallbackPolyline = new google.maps.Polyline({
        geodesic: true,
        strokeColor: "#ffc107",
        strokeOpacity: 0.7,
        strokeWeight: 3,
        map: this.map,
      });
    }

    this.fallbackPolyline.setPath(routePoints);

    if (routePoints.length > 0) {
      this.map.fitBounds(bounds, { padding: 50 });
    }
  }

  // 🆕 Calcular distancia entre dos puntos (en km)
  calculateDistance(point1, point2) {
    const R = 6371; // Radio de la Tierra en km
    const dLat = this.toRad(point2.lat - point1.lat);
    const dLng = this.toRad(point2.lng - point1.lng);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRad(point1.lat)) *
        Math.cos(this.toRad(point2.lat)) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  toRad(degrees) {
    return degrees * (Math.PI / 180);
  }

  startPolling() {
    this.pollInterval = setInterval(() => {
      this.fetchCurrentPosition();
    }, 10000); // Cada 10 segundos
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }
  }

  async fetchCurrentPosition() {
    try {
      const response = await fetch(
        `/delivery_plans/${this.deliveryPlanIdValue}.json`
      );
      const data = await response.json();

      if (data.current_lat && data.current_lng) {
        this.updateDriverPosition(data.current_lat, data.current_lng);
        this.updateLastSeenTime(data.last_seen_at);
      }

      if (data.assignments) {
        this.updateAssignmentStatuses(data.assignments);
      }
    } catch (error) {
      console.error("Error fetching position:", error);
    }
  }

  updateDriverPosition(lat, lng) {
    const oldLat = this.currentLatValue;
    const oldLng = this.currentLngValue;

    this.currentLatValue = lat;
    this.currentLngValue = lng;

    const newPosition = { lat, lng };
    this.driverMarker.setPosition(newPosition);

    // Centrar mapa suavemente solo si el conductor se movió significativamente
    if (oldLat && oldLng) {
      const distance = this.calculateDistance(
        { lat: oldLat, lng: oldLng },
        newPosition
      );
      if (distance > 0.1) {
        // Más de 100 metros
        this.map.panTo(newPosition);
      }
    } else {
      this.map.panTo(newPosition);
    }

    // 🆕 Recalcular ruta con nueva posición
    this.updateRouteWithDirections();
  }

  updateLastSeenTime(timestamp) {
    if (timestamp) {
      const date = new Date(timestamp);
      const now = new Date();
      const diffSeconds = Math.floor((now - date) / 1000);

      let timeText;
      if (diffSeconds < 60) {
        timeText = "Hace unos segundos";
      } else if (diffSeconds < 3600) {
        timeText = `Hace ${Math.floor(diffSeconds / 60)} minutos`;
      } else {
        timeText = date.toLocaleTimeString();
      }

      const element = document.getElementById("driver-last-seen");
      if (element) {
        element.textContent = timeText;
      }
    }
  }

  updateAssignmentStatuses(assignments) {
    let statusChanged = false;

    assignments.forEach((assignment) => {
      const markerData = this.deliveryMarkers.find(
        (m) => m.assignment.id === assignment.id
      );
      if (markerData && markerData.assignment.status !== assignment.status) {
        statusChanged = true;
        markerData.assignment.status = assignment.status;

        // Actualizar color del marker
        markerData.marker.setIcon({
          path: google.maps.SymbolPath.CIRCLE,
          scale: 12,
          fillColor: this.getMarkerColor(assignment.status),
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2,
        });
      }
    });

    // 🆕 Solo recalcular ruta si cambió algún estado
    if (statusChanged) {
      this.updateRouteWithDirections();
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
