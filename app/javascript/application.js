import "@hotwired/turbo-rails"
import "controllers"
document.addEventListener("turbo:load", function () {
    // Inicializa tooltips de Bootstrap (si usas tooltips)
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
    tooltipTriggerList.forEach(function (tooltipTriggerEl) {
        new bootstrap.Tooltip(tooltipTriggerEl)
    })
});

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