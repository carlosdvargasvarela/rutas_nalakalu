import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        // Seleccionar/deseleccionar todos los checkboxes
        const selectAll = this.element.querySelector("#select-all")
        if (selectAll) {
            selectAll.addEventListener("change", function () {
                const checkboxes = document.querySelectorAll(".delivery-checkbox")
                checkboxes.forEach(cb => { cb.checked = selectAll.checked })
            })
        }

        // Tooltips para notas de productos
        const tooltipTriggerList = [].slice.call(this.element.querySelectorAll('[data-bs-toggle="tooltip"]'))
        tooltipTriggerList.forEach(function (tooltipTriggerEl) {
            new bootstrap.Tooltip(tooltipTriggerEl)
        })
    }
}