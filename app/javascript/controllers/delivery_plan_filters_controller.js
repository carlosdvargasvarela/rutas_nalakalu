// app/javascript/controllers/delivery_plan_filters_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["advancedFilters", "chevron", "quickFilters"];

  connect() {
    // Si hay filtros activos, mostrar el panel expandido
    const hasActiveFilters = this.element.querySelector(
      ".badge.bg-primary.rounded-pill",
    );
    if (hasActiveFilters) {
      this.expand();
    }
  }

  toggleFilters(e) {
    const isCollapsed =
      this.advancedFiltersTarget.classList.contains("filters-collapsed");
    isCollapsed ? this.expand() : this.collapse();
  }

  expand() {
    this.advancedFiltersTarget.classList.remove("filters-collapsed");
    this.chevronTarget.style.transform = "rotate(180deg)";
  }

  collapse() {
    this.advancedFiltersTarget.classList.add("filters-collapsed");
    this.chevronTarget.style.transform = "rotate(0deg)";
  }

  stopPropagation(e) {
    e.stopPropagation();
  }
}
