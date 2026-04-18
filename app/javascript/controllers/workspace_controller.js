import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["card"];
  static classes = ["active"];

  select(event) {
    const selectedCard = event.currentTarget;

    this.cardTargets.forEach((card) => {
      card.classList.remove(...this.activeClasses);
    });

    selectedCard.classList.add(...this.activeClasses);
  }
}
