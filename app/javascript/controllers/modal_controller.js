import { Controller } from "@hotwired/stimulus";
import { Modal } from "bootstrap";

export default class extends Controller {
  connect() {
    this._modal = new Modal(this.element);

    // Abrir modal cuando el frame recibe contenido (navegación por URL)
    this._frameLoadHandler = (event) => {
      if (event.target.id === "modal" && event.target.innerHTML.trim() !== "") {
        this._modal.show();
      }
    };
    document.addEventListener("turbo:frame-load", this._frameLoadHandler);

    // El modal es data-turbo-permanent: sobrevive a las visitas de página
    // completa (p. ej. un form con turbo_frame "_top" que redirige). Cerrarlo.
    this._visitHandler = () => this._modal.hide();
    document.addEventListener("turbo:visit", this._visitHandler);

    const frame = document.getElementById("modal");
    if (frame) {
      this._observer = new MutationObserver(() => {
        if (frame.innerHTML.trim() === "") {
          this._modal.hide();
        }
      });
      this._observer.observe(frame, { childList: true, subtree: true });
    }

    // Limpiar backdrop al cerrar
    this.element.addEventListener("hidden.bs.modal", () => {
      if (frame) {
        frame.removeAttribute("src");
        frame.innerHTML = "";
      }
      document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());
      document.body.classList.remove("modal-open");
      document.body.style = "";
    });
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this._frameLoadHandler);
    document.removeEventListener("turbo:visit", this._visitHandler);
    this._observer?.disconnect();
  }
}
