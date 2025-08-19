// app/javascript/controllers/bootstrap_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.init = this.init.bind(this)
    this.teardown = this.teardown.bind(this)

    // Inicializa de una vez al conectar
    this.init()

    // Re-inicializa en navegaciones Turbo y cargas de frames
    document.addEventListener("turbo:load", this.init)
    document.addEventListener("turbo:frame-load", this.init)

    // Limpia antes del cache
    document.addEventListener("turbo:before-cache", this.teardown)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.init)
    document.removeEventListener("turbo:frame-load", this.init)
    document.removeEventListener("turbo:before-cache", this.teardown)
    this.teardown()
  }

  init() {
    // Tooltips
    this.tooltipInstances = Array.from(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
      .map(el => new bootstrap.Tooltip(el))

    // Popovers
    this.popoverInstances = Array.from(document.querySelectorAll('[data-bs-toggle="popover"]'))
      .map(el => new bootstrap.Popover(el))

    // Cierra dropdowns “atorados” si hubiera
    document.querySelectorAll(".dropdown-menu.show").forEach(menu => {
      bootstrap.Dropdown.getInstance(menu)?.hide()
    })
  }

  teardown() {
    this.tooltipInstances?.forEach(instance => instance.dispose())
    this.popoverInstances?.forEach(instance => instance.dispose())

    // Cierra modales abiertos antes de cachear
    document.querySelectorAll(".modal.show").forEach(modalEl => {
      bootstrap.Modal.getInstance(modalEl)?.hide()
    })
  }
}