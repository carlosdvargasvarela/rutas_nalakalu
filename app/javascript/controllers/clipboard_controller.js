// app/javascript/controllers/clipboard_controller.js
import { Controller } from "@hotwired/stimulus";

// Copia texto al portapapeles sin disparar la navegación del elemento
// padre (p. ej. una tarjeta envuelta en un <a>).
export default class extends Controller {
  static values = { text: String };

  copy(event) {
    event.preventDefault();
    event.stopPropagation();
    if (!this.textValue) return;

    // event.currentTarget se vuelve null después de que el evento termina de
    // despacharse, así que hay que capturarlo antes del .then() async.
    const btn = event.currentTarget;
    navigator.clipboard.writeText(this.textValue).then(() => this._flash(btn));
  }

  _flash(btn) {
    const original = btn.innerHTML;
    btn.innerHTML = '<i class="bi bi-check-lg"></i>';
    setTimeout(() => {
      btn.innerHTML = original;
    }, 1500);
  }
}
