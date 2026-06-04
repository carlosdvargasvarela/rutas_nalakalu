import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "sourceSelect",
    "destinationSelect",
    "sameShowroomAlert",
    "interSalaInfo",
    "deliveryDateDestinationWrapper",
    "deliveryDateDestinationInput",
    "dateLabel",
    "notesWrapper",
    "notesInterSalaHint",
    "itemTemplate",
    "submitButton",
  ];

  connect() {
    this._itemIndex = this.element.querySelectorAll("[data-item-row]").length;
  }

  validateShowrooms() {
    const sourceVal = this.hasSourceSelectTarget
      ? this.sourceSelectTarget.value
      : this.element.querySelector("select[name='source_showroom_id']")?.value;
    const destVal = this.destinationSelectTarget?.value;

    const same = sourceVal && destVal && sourceVal === destVal;
    this.sameShowroomAlertTarget.classList.toggle("d-none", !same);
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = same;
    }

    const sourceOption = this.hasSourceSelectTarget
      ? this.sourceSelectTarget.querySelector(`option[value="${sourceVal}"]`)
      : this.element.querySelector(`select[name='source_showroom_id'] option[value="${sourceVal}"]`);
    const destOption = this.destinationSelectTarget?.querySelector(`option[value="${destVal}"]`);

    const sourceIsMain = sourceOption?.dataset?.isMain === "true";
    const destIsMain = destOption?.dataset?.isMain === "true";
    const isInterSala = !!(sourceVal && destVal && !same && !sourceIsMain && !destIsMain);

    this._applyInterSalaState(isInterSala);
  }

  _applyInterSalaState(isInterSala) {
    if (this.hasInterSalaInfoTarget) {
      this.interSalaInfoTarget.classList.toggle("d-none", !isInterSala);
    }

    if (this.hasDeliveryDateDestinationWrapperTarget) {
      this.deliveryDateDestinationWrapperTarget.classList.toggle("d-none", !isInterSala);
      if (this.hasDeliveryDateDestinationInputTarget) {
        this.deliveryDateDestinationInputTarget.required = isInterSala;
      }
    }

    if (this.hasDateLabelTarget) {
      this.dateLabelTarget.textContent = isInterSala
        ? "Fecha de recolección en sala origen"
        : "Fecha del movimiento";
    }

    if (this.hasNotesInterSalaHintTarget) {
      this.notesInterSalaHintTarget.classList.toggle("d-none", !isInterSala);
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
