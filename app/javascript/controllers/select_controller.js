import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
    connect() {
        this.tomSelect = new TomSelect(this.element, {
            create: false,   // evitamos que el usuario escriba opciones nuevas
            sortField: {
                field: "text",
                direction: "asc"
            },
            maxOptions: 100, // límite de resultados
            placeholder: this.element.dataset.placeholder || "Buscar..."
        })
    }

    disconnect() {
        if (this.tomSelect) {
            this.tomSelect.destroy()
        }
    }
}