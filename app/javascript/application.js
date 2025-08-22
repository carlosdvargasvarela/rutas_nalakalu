// app/javascript/application.js
// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from "bootstrap"

// Expón bootstrap globalmente para que esté disponible en Stimulus controllers
window.bootstrap = bootstrap

// Limpieza antes del cache de Turbo (evita estados pegados entre navegaciones)
document.addEventListener("turbo:before-cache", () => {
    // Cierra modales abiertos
    document.querySelectorAll(".modal.show").forEach(el => {
        const modalInstance = bootstrap.Modal.getInstance(el)
        if (modalInstance) modalInstance.hide()
    })

    // Cierra dropdowns abiertos
    document.querySelectorAll(".dropdown-menu.show").forEach(menu => {
        const toggle = menu.previousElementSibling
        if (toggle) {
            const dropdownInstance = bootstrap.Dropdown.getInstance(toggle)
            if (dropdownInstance) dropdownInstance.hide()
        }
    })
})