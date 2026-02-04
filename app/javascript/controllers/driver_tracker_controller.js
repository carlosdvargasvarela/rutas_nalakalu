// app/javascript/controllers/driver_tracker_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    planId: Number,
    interval: { type: Number, default: 15000 }, // 15 segundos por defecto
    url: String,
  };

  static targets = ["status", "lastUpdate"];

  connect() {
    console.log("🚚 Driver Tracker conectado");
    this.positions = [];
    this.watchId = null;
    this.syncTimer = null;
    this.isTracking = false;

    // Cargar posiciones pendientes del localStorage
    this.loadPendingPositions();

    // Iniciar tracking automáticamente
    this.startTracking();
  }

  disconnect() {
    console.log("🚚 Driver Tracker desconectado");
    this.stopTracking();
  }

  startTracking() {
    if (this.isTracking) return;

    if (!navigator.geolocation) {
      this.showError("Tu dispositivo no soporta geolocalización");
      return;
    }

    this.isTracking = true;
    this.updateStatus("Iniciando GPS...", "warning");

    // Opciones de geolocalización
    const options = {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0,
    };

    // Iniciar watchPosition
    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.onPositionSuccess(position),
      (error) => this.onPositionError(error),
      options,
    );

    // Iniciar sincronización periódica
    this.syncTimer = setInterval(() => {
      this.syncPositions();
    }, this.intervalValue);

    console.log("✅ Tracking GPS iniciado");
  }

  stopTracking() {
    if (!this.isTracking) return;

    if (this.watchId) {
      navigator.geolocation.clearWatch(this.watchId);
      this.watchId = null;
    }

    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }

    this.isTracking = false;
    this.updateStatus("GPS detenido", "secondary");
    console.log("⏹️ Tracking GPS detenido");
  }

  onPositionSuccess(position) {
    const coords = {
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
      accuracy: position.coords.accuracy,
      speed: position.coords.speed,
      heading: position.coords.heading,
      timestamp: new Date().toISOString(),
    };

    console.log("📍 Nueva posición capturada:", coords);

    // Agregar a la cola
    this.positions.push(coords);

    // Actualizar UI
    this.updateStatus(
      `GPS activo (±${Math.round(coords.accuracy)}m)`,
      "success",
    );
    this.updateLastUpdate();

    // Intentar sincronizar inmediatamente si hay posiciones acumuladas
    if (this.positions.length >= 1) {
      this.syncPositions();
    }
  }

  onPositionError(error) {
    let message = "Error de GPS";

    switch (error.code) {
      case error.PERMISSION_DENIED:
        message = "Permiso de ubicación denegado";
        break;
      case error.POSITION_UNAVAILABLE:
        message = "Ubicación no disponible";
        break;
      case error.TIMEOUT:
        message = "Tiempo de espera agotado";
        break;
    }

    console.error("❌ Error GPS:", message, error);
    this.updateStatus(message, "danger");
  }

  async syncPositions() {
    if (this.positions.length === 0) {
      console.log("📭 No hay posiciones para sincronizar");
      return;
    }

    const positionsToSync = [...this.positions];
    console.log(`📤 Sincronizando ${positionsToSync.length} posiciones...`);

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          delivery_plan_id: this.planIdValue,
          positions: positionsToSync,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        console.log("✅ Posiciones sincronizadas:", data);

        // Limpiar posiciones sincronizadas
        this.positions = [];
        this.clearPendingPositions();

        this.updateStatus(
          `GPS activo - ${data.saved || positionsToSync.length} puntos guardados`,
          "success",
        );
      } else {
        throw new Error(`HTTP ${response.status}`);
      }
    } catch (error) {
      console.error("❌ Error al sincronizar:", error);

      // Guardar en localStorage para reintentar después
      this.savePendingPositions();

      this.updateStatus("Sin conexión - guardando offline", "warning");
    }
  }

  // Gestión de localStorage para posiciones pendientes
  savePendingPositions() {
    try {
      const key = `pending_positions_${this.planIdValue}`;
      localStorage.setItem(key, JSON.stringify(this.positions));
      console.log("💾 Posiciones guardadas en localStorage");
    } catch (error) {
      console.error("Error guardando en localStorage:", error);
    }
  }

  loadPendingPositions() {
    try {
      const key = `pending_positions_${this.planIdValue}`;
      const stored = localStorage.getItem(key);

      if (stored) {
        this.positions = JSON.parse(stored);
        console.log(
          `📥 ${this.positions.length} posiciones cargadas desde localStorage`,
        );
      }
    } catch (error) {
      console.error("Error cargando desde localStorage:", error);
      this.positions = [];
    }
  }

  clearPendingPositions() {
    try {
      const key = `pending_positions_${this.planIdValue}`;
      localStorage.removeItem(key);
    } catch (error) {
      console.error("Error limpiando localStorage:", error);
    }
  }

  // Métodos de UI
  updateStatus(message, type = "secondary") {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message;
      this.statusTarget.className = `badge bg-${type}`;
    }
  }

  updateLastUpdate() {
    if (this.hasLastUpdateTarget) {
      const now = new Date();
      this.lastUpdateTarget.textContent = now.toLocaleTimeString("es-CR");
    }
  }

  // Obtener CSRF token
  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }

  // Acción manual para forzar sincronización
  forceSync() {
    console.log("🔄 Sincronización forzada");
    this.syncPositions();
  }
}
