// app/javascript/application.js
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from "bootstrap"

window.bootstrap = bootstrap

document.addEventListener("turbo:load", () => {
    // Inicializar tooltips/dropdowns refrescados con Turbo
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
        if (!bootstrap.Tooltip.getInstance(el)) {
            new bootstrap.Tooltip(el)
        }
    })

    document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(el => {
        if (!bootstrap.Dropdown.getInstance(el)) {
            new bootstrap.Dropdown(el)
        }
    })
})