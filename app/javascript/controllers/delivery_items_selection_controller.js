// app/javascript/controllers/delivery_items_selection_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "bulkButton", "count"];

  connect() {
    this.updateUI();
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = event.target.checked;
    });
    this.updateUI();
  }

  updateUI() {
    const selectedCount = this.checkboxTargets.filter((c) => c.checked).length;

    if (this.hasBulkButtonTarget) {
      this.bulkButtonTarget.disabled = selectedCount === 0;
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = selectedCount;
    }
  }

  prepareReschedule(event) {
    const selectedIds = this.checkboxTargets
      .filter((c) => c.checked)
      .map((c) => c.value);

    if (selectedIds.length === 0) return;

    const url = new URL(
      event.currentTarget.dataset.url,
      window.location.origin,
    );
    url.searchParams.set("item_ids", selectedIds.join(","));

    const modalFrame = document.getElementById("modal");
    if (modalFrame) {
      modalFrame.src = url.toString();
    }
  }
}
