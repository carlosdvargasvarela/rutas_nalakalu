import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "destinationSelect",
    "sameShowroomAlert",
    "itemTemplate",
    "submitButton",
  ];

  connect() {
    this._itemIndex = this.element.querySelectorAll("[data-item-row]").length;
  }

  validateShowrooms() {
    const sourceVal = this.element.querySelector(
      "select[name='source_showroom_id']"
    )?.value;
    const destVal = this.destinationSelectTarget?.value;

    const same = sourceVal && destVal && sourceVal === destVal;
    this.sameShowroomAlertTarget.classList.toggle("d-none", !same);
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = same;
    }
  }

  addItem() {
    const template = this.itemTemplateTarget.innerHTML.replaceAll(
      "__INDEX__",
      this._itemIndex++
    );
    const container = this.element.querySelector("#movement-items-container");
    container.insertAdjacentHTML("beforeend", template);
  }

  removeItem(event) {
    const row = event.currentTarget.closest("[data-item-row]");
    row?.remove();
  }
}
