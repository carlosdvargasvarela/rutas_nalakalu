/*import { Controller } from "@hotwired/stimulus";
import TomSelect from "tom-select";

export default class extends Controller {
  connect() {
    console.log("TomSelectController connected on:", this.element);

    // Verificar si ya tiene TomSelect inicializado
    if (this.element.tomselect) {
      console.log("TomSelect already initialized, skipping...");
      return;
    }

    this.tomSelect = new TomSelect(this.element, {
      create: false,
      sortField: {
        field: "text",
        direction: "asc",
      },
      placeholder: this.element.getAttribute("placeholder") || "Seleccionar...",
      allowEmptyOption: true,
      maxOptions: null,
      onInitialize: function () {
        console.log("TomSelect initialized successfully");
      },
    });

    // Guardar referencia en el elemento
    this.element.tomselect = this.tomSelect;
  }

  disconnect() {
    if (this.tomSelect) {
      this.tomSelect.destroy();
      delete this.element.tomselect;
    }
  }
}*/
