import { Controller } from "@hotwired/stimulus";

// Alterna entre el panel de mapa y el de proveedor en el form de mandado.
// Solo el panel activo debe enviarse: los campos del panel oculto se
// deshabilitan (los inputs disabled no viajan en el submit).
export default class extends Controller {
  static targets = ["mapPane", "vendorPane"];

  connect() {
    const useVendor = !this.mapPaneTarget.classList.contains("d-none")
      ? false
      : true;
    this._setDisabled(this.mapPaneTarget, useVendor);
    this._setDisabled(this.vendorPaneTarget, !useVendor);
  }

  toggle(event) {
    const useVendor = event.target.value === "vendor";
    this.mapPaneTarget.classList.toggle("d-none", useVendor);
    this.vendorPaneTarget.classList.toggle("d-none", !useVendor);
    this._setDisabled(this.mapPaneTarget, useVendor);
    this._setDisabled(this.vendorPaneTarget, !useVendor);
  }

  _setDisabled(pane, disabled) {
    pane.querySelectorAll("input, select, textarea").forEach((el) => {
      el.disabled = disabled;
    });
  }
}
