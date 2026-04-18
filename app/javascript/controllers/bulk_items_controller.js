// app/javascript/controllers/bulk_items_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "toolbar", "count", "selectAll"];

  connect() {
    this.updateToolbar();
  }

  toggle() {
    this.updateToolbar();
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked;
    this.checkboxTargets.forEach((cb) => (cb.checked = checked));
    this.updateToolbar();
  }

  updateToolbar() {
    const selected = this.selectedIds();
    const count = selected.length;

    this.countTarget.textContent =
      count === 0
        ? "Seleccionar items"
        : `${count} item${count > 1 ? "s" : ""} seleccionado${count > 1 ? "s" : ""}`;

    this.toolbarTarget.classList.toggle("d-none", count === 0);

    // Sync estado del selectAll
    const total = this.checkboxTargets.length;
    this.selectAllTarget.indeterminate = count > 0 && count < total;
    this.selectAllTarget.checked = count === total && total > 0;
  }

  selectedIds() {
    return this.checkboxTargets
      .filter((cb) => cb.checked)
      .map((cb) => cb.value);
  }

  // Inyecta los IDs seleccionados en el form antes de submit
  prepareForm(event) {
    const form = event.currentTarget.closest("form");
    const ids = this.selectedIds();

    // Limpiar inputs previos
    form
      .querySelectorAll("input[name='item_ids[]']")
      .forEach((el) => el.remove());

    ids.forEach((id) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "item_ids[]";
      input.value = id;
      form.appendChild(input);
    });
  }
}
