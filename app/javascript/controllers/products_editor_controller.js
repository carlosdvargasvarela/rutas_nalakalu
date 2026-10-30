import { Controller } from "@hotwired/stimulus";

const normalize = (text) =>
  text.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim();

// Filas nuevas y buscador de la pantalla de productos de una entrega.
export default class extends Controller {
  static targets = ["rows", "template", "search", "count"];

  add() {
    this.rowsTarget.append(this.templateTarget.content.cloneNode(true));
    this.rowsTarget.lastElementChild.querySelector("input")?.focus();
  }

  remove(event) {
    event.target.closest("tr").remove();
  }

  // Solo oculta: las filas filtradas siguen en el form y se guardan igual.
  filter() {
    const term = normalize(this.searchTarget.value);
    const rows = [...this.rowsTarget.querySelectorAll("tr:not([data-new-row])")];
    let visible = 0;

    rows.forEach((row) => {
      const name = row.querySelector("input[type=text]")?.value ?? row.textContent;
      const matches = normalize(name).includes(term);
      row.hidden = !matches;
      if (matches) visible += 1;
    });

    this.countTarget.textContent = term ? `${visible} de ${rows.length}` : "";
  }

  // Un campo requerido oculto bloquearía el envío sin mostrar el error.
  clearSearch() {
    this.searchTarget.value = "";
    this.filter();
  }
}
