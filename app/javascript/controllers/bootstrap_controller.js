// app/javascript/controllers/bootstrap_controller.js
import { Controller } from "@hotwired/stimulus"
import { Tooltip } from "bootstrap"

export default class extends Controller {
  connect() {
    // Solo inicializar una vez al conectar
    this.initializeBootstrap()
    new Tooltip(this.element)
  }

  initializeBootstrap() {
    if (typeof bootstrap === 'undefined') return

    // Solo inicializar elementos que no tengan instancia ya
    this.element.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      if (!bootstrap.Tooltip.getInstance(el)) {
        new bootstrap.Tooltip(el)
      }
    })

    this.element.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
      if (!bootstrap.Popover.getInstance(el)) {
        new bootstrap.Popover(el)
      }
    })
  }

  disconnect() {
    // Limpiar instancias al desconectar
    if (typeof bootstrap === 'undefined') return

    this.element.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      const instance = bootstrap.Tooltip.getInstance(el)
      if (instance) instance.dispose()
    })

    this.element.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
      const instance = bootstrap.Popover.getInstance(el)
      if (instance) instance.dispose()
    })
  }
}