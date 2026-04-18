import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["card"];
  static classes = ["active"];

  select(event) {
    // 1. Remover la clase activa de todas las tarjetas
    this.cardTargets.forEach((card) => {
      card.classList.remove(...this.activeClasses);
    });

    // 2. Agregar la clase activa a la tarjeta clickeada (o su contenedor)
    const selected_card = event.currentTarget;
    selected_card.classList.add(...this.activeClasses);
  }
}
