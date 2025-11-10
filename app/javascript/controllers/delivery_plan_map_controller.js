// app/javascript/controllers/delivery_plan_map_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["map"];
  static values = {
    apiKey: String,
    points: Array,
  };

  connect() {
    if (this.isGoogleMapsReady()) {
      this.initMap();
    } else {
      this.loadGoogleMaps();
    }
  }

  loadGoogleMaps() {
    if (document.querySelector("#google-maps-script")) {
      this.waitForGoogleMaps();
      return;
    }
    const script = document.createElement("script");
    script.id = "google-maps-script";
    script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKeyValue}&libraries=geometry`;
    script.async = true;
    script.defer = true;
    script.onload = () => this.waitForGoogleMaps();
    document.head.appendChild(script);
  }

  waitForGoogleMaps() {
    const check = () => {
      if (this.isGoogleMapsReady()) {
        this.initMap();
      } else {
        setTimeout(check, 200);
      }
    };
    check();
  }

  isGoogleMapsReady() {
    return typeof google !== "undefined" && google.maps;
  }

  initMap() {
    if (!this.pointsValue.length) return;

    const center = {
      lat: parseFloat(this.pointsValue[0].lat),
      lng: parseFloat(this.pointsValue[0].lng),
    };

    this.map = new google.maps.Map(this.mapTarget, {
      center,
      zoom: 12,
      mapTypeControl: false,
    });

    this.bounds = new google.maps.LatLngBounds();
    this.directionsService = new google.maps.DirectionsService();
    this.directionsRenderer = new google.maps.DirectionsRenderer({
      map: this.map,
      suppressMarkers: true, // Usamos nuestros propios markers
      polylineOptions: {
        strokeColor: "#007bff",
        strokeOpacity: 0.7,
        strokeWeight: 4,
      },
    });

    this.addMarkers();
    this.drawRoute();
  }

  addMarkers() {
    this.pointsValue.forEach((p, idx) => {
      const position = { lat: parseFloat(p.lat), lng: parseFloat(p.lng) };

      // Marker personalizado con número de parada
      const marker = new google.maps.Marker({
        position,
        map: this.map,
        label: {
          text: String(p.stop_order || idx + 1),
          color: "white",
          fontSize: "14px",
          fontWeight: "bold",
        },
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 12,
          fillColor:
            idx === 0
              ? "#28a745"
              : idx === this.pointsValue.length - 1
              ? "#dc3545"
              : "#007bff",
          fillOpacity: 1,
          strokeColor: "white",
          strokeWeight: 2,
        },
        title: `${p.order_number} - ${p.client}`,
      });

      const infowindow = new google.maps.InfoWindow({
        content: `
          <div style="min-width: 200px;">
            <strong style="color: #007bff;">Parada ${
              p.stop_order || idx + 1
            }</strong><br>
            <strong>Pedido:</strong> ${p.order_number}<br>
            <strong>Cliente:</strong> ${p.client}<br>
            <strong>Dirección:</strong> ${p.address}<br>
            <strong>Fecha:</strong> ${p.date}
          </div>
        `,
      });

      marker.addListener("click", () => {
        infowindow.open(this.map, marker);
      });

      this.bounds.extend(position);
    });
  }

  drawRoute() {
    if (this.pointsValue.length < 2) {
      this.map.fitBounds(this.bounds);
      return;
    }

    // Preparar origen, destino y waypoints
    const origin = {
      lat: parseFloat(this.pointsValue[0].lat),
      lng: parseFloat(this.pointsValue[0].lng),
    };

    const destination = {
      lat: parseFloat(this.pointsValue[this.pointsValue.length - 1].lat),
      lng: parseFloat(this.pointsValue[this.pointsValue.length - 1].lng),
    };

    // Waypoints intermedios (máximo 25 por request según Google)
    const waypoints = this.pointsValue.slice(1, -1).map((p) => ({
      location: {
        lat: parseFloat(p.lat),
        lng: parseFloat(p.lng),
      },
      stopover: true,
    }));

    // Si hay más de 25 waypoints, dividir en múltiples requests
    if (waypoints.length > 25) {
      this.drawRouteInBatches(origin, destination, waypoints);
    } else {
      this.requestDirections(origin, destination, waypoints);
    }
  }

  requestDirections(origin, destination, waypoints) {
    const request = {
      origin,
      destination,
      waypoints,
      travelMode: google.maps.TravelMode.DRIVING,
      region: "CR", // Costa Rica
      optimizeWaypoints: false, // Mantener el orden de las paradas
    };

    this.directionsService.route(request, (result, status) => {
      if (status === google.maps.DirectionsStatus.OK) {
        this.directionsRenderer.setDirections(result);

        // Mostrar distancia y tiempo total
        this.displayRouteInfo(result);
      } else {
        console.error("Error al calcular la ruta:", status);
        // Fallback: dibujar polyline simple
        this.drawPolylineFallback();
      }
    });
  }

  drawRouteInBatches(origin, destination, waypoints) {
    // Para rutas con más de 25 paradas, dividir en segmentos
    console.warn("Ruta con más de 25 paradas. Dividiendo en segmentos...");

    const batchSize = 25;
    const batches = [];

    for (let i = 0; i < waypoints.length; i += batchSize) {
      batches.push(waypoints.slice(i, i + batchSize));
    }

    // Por ahora, solo tomar los primeros 25 waypoints
    // TODO: Implementar lógica para múltiples requests
    this.requestDirections(origin, destination, waypoints.slice(0, 25));
  }

  drawPolylineFallback() {
    // Fallback: línea simple si falla Directions API
    const routePath = new google.maps.Polyline({
      path: this.pointsValue.map((p) => ({
        lat: parseFloat(p.lat),
        lng: parseFloat(p.lng),
      })),
      geodesic: true,
      strokeColor: "#ffc107",
      strokeOpacity: 0.7,
      strokeWeight: 3,
      map: this.map,
    });

    this.map.fitBounds(this.bounds);
  }

  displayRouteInfo(result) {
    // Calcular distancia y tiempo total
    let totalDistance = 0;
    let totalDuration = 0;

    result.routes[0].legs.forEach((leg) => {
      totalDistance += leg.distance.value;
      totalDuration += leg.duration.value;
    });

    const distanceKm = (totalDistance / 1000).toFixed(1);
    const durationMin = Math.round(totalDuration / 60);

    console.log(`Ruta calculada: ${distanceKm} km, ${durationMin} min`);

    // Opcional: Mostrar en la UI
    this.showRouteStats(distanceKm, durationMin);
  }

  showRouteStats(distance, duration) {
    // Buscar o crear elemento para mostrar stats
    let statsEl = document.querySelector("[data-route-stats]");

    if (!statsEl) {
      statsEl = document.createElement("div");
      statsEl.setAttribute("data-route-stats", "");
      statsEl.className = "alert alert-info mt-2 mb-0";
      this.mapTarget.parentElement.appendChild(statsEl);
    }

    statsEl.innerHTML = `
      <i class="bi bi-info-circle me-2"></i>
      <strong>Distancia total:</strong> ${distance} km &nbsp;|&nbsp;
      <strong>Tiempo estimado:</strong> ${duration} min
    `;
  }
}
