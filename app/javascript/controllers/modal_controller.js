import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.modal = new window.bootstrap.Modal(this.element, {
      backdrop: true,
      keyboard: true,
    });

    const frame = this.element.querySelector('turbo-frame[id="modal"]');
    if (!frame) return;

    this.frame = frame;
    this._isOpen = false;

    this.observer = new MutationObserver(() => {
      const hasContent = frame.innerHTML.trim() !== "";

      if (hasContent && !this._isOpen) {
        // Contenido nuevo → abrir modal
        this._isOpen = true;
        this.modal.show();

        this.element.addEventListener(
          "hidden.bs.modal",
          () => {
            this._isOpen = false;
            // Solo limpiar si el frame aún tiene contenido
            // (no limpiar si ya fue vaciado por Turbo Stream)
            if (frame.innerHTML.trim() !== "") {
              frame.innerHTML = "";
            }
          },
          { once: true },
        );
      } else if (!hasContent && this._isOpen) {
        // Turbo Stream vació el frame → cerrar modal sin limpiar
        this._isOpen = false;
        this.modal.hide();
        this._cleanup();
      }
    });

    this.observer.observe(frame, { childList: true, subtree: true });
  }

  _cleanup() {
    // Pequeño delay para que Bootstrap termine su animación
    setTimeout(() => {
      document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());
      document.body.classList.remove("modal-open");
      document.body.style.removeProperty("overflow");
      document.body.style.removeProperty("padding-right");
    }, 300);
  }

  disconnect() {
    this.observer?.disconnect();
    this.modal?.dispose();
  }
}
