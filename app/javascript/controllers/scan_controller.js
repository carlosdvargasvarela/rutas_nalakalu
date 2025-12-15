// app/javascript/controllers/scan_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "result"];
  static values = {
    url: String,
  };

  connect() {
    console.log("Scan controller connected");
    this.setupScanner();
  }

  setupScanner() {
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("keypress", (event) => {
        if (event.key === "Enter") {
          event.preventDefault();
          this.processCode(this.inputTarget.value);
        }
      });
    }
  }

  async processCode(code) {
    if (!code || code.trim() === "") return;

    console.log("Processing code:", code);

    try {
      const response = await fetch(
        `${this.urlValue}?code=${encodeURIComponent(code)}`,
        {
          headers: {
            Accept: "application/json",
          },
        }
      );

      const data = await response.json();

      if (data.success) {
        this.showSuccess(data.message);
        this.highlightItem(data.item_id);
      } else {
        this.showError(data.message);
      }

      this.inputTarget.value = "";
      this.inputTarget.focus();
    } catch (error) {
      console.error("Error processing code:", error);
      this.showError("Error al procesar el código");
    }
  }

  showSuccess(message) {
    this.dispatchToast(message, "success");
  }

  showError(message) {
    this.dispatchToast(message, "error");
  }

  dispatchToast(message, type) {
    const event = new CustomEvent("show-toast", {
      detail: { message, type },
      bubbles: true,
    });
    this.element.dispatchEvent(event);
  }

  highlightItem(itemId) {
    const element = document.getElementById(`delivery_item_${itemId}`);
    if (element) {
      element.scrollIntoView({ behavior: "smooth", block: "center" });
      element.classList.add("highlight-flash");
      setTimeout(() => element.classList.remove("highlight-flash"), 2000);
    }
  }

  // Activar cámara para escaneo QR (requiere librería externa)
  activateCamera(event) {
    event.preventDefault();
    // Implementar con html5-qrcode o similar
    console.log("Camera activation - to be implemented");
  }
}
