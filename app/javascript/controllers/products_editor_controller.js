import { Controller } from "@hotwired/stimulus";

// Filas nuevas de la pantalla de productos de una entrega.
export default class extends Controller {
  static targets = ["rows", "template"];

  add() {
    this.rowsTarget.append(this.templateTarget.content.cloneNode(true));
    this.rowsTarget.lastElementChild.querySelector("input")?.focus();
  }

  remove(event) {
    event.target.closest("tr").remove();
  }
}
