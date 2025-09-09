import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("turbo:load", () => {
    // Inicializar Bootstrap como ya tenías
    initBootstrap()

    // Marcar nav activo según la URL actual
    setActiveNavLink()
})

function initBootstrap() {
    document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(el => {
        new bootstrap.Dropdown(el)
    })
}

function setActiveNavLink() {
    const path = window.location.pathname
    const navLinks = document.querySelectorAll(".navbar-nav .nav-link")

    navLinks.forEach(link => {
        // Quitar active en todos
        link.classList.remove("active")

        // Si la URL actual comienza con el href del link, marcarlo
        if (link.getAttribute("href") === path ||
            (link.getAttribute("href") !== "/" && path.startsWith(link.getAttribute("href")))) {
            link.classList.add("active")
        }
    })
}