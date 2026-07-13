// app/javascript/controllers/workspace_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["card"];
  static classes = ["active"];
  static values = { detailFrame: { type: String, default: "delivery_detail" } };

  connect() {
    this.updateLinks();
    this._resizeHandler = () => this.updateLinks();
    window.addEventListener("resize", this._resizeHandler);
  }

  disconnect() {
    window.removeEventListener("resize", this._resizeHandler);
  }

  updateLinks() {
    const isDesktop = window.innerWidth >= 992;
    this.element.querySelectorAll("a[data-card-link]").forEach((link) => {
      // En móvil navegación completa (_top)
      link.dataset.turboFrame = isDesktop ? this.detailFrameValue : "_top";
    });
  }

  select(event) {
    if (window.innerWidth < 992) return;

    this.cardTargets.forEach((card) =>
      card.classList.remove(...this.activeClasses),
    );
    event.currentTarget.classList.add(...this.activeClasses);
  }
}
