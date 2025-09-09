import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("turbo:load", () => {
    // Inicializar dropdowns
    document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(el => {
        new bootstrap.Dropdown(el)
    })

    // Inicializar tooltips
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
        new bootstrap.Tooltip(el)
    })

    // Inicializar popovers
    document.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
        new bootstrap.Popover(el)
    })
})