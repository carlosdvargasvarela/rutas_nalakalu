// app/javascript/controllers/bootstrap_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.initializeBootstrap()

    document.addEventListener("turbo:load", () => {
      this.initializeBootstrap()
    })
  }

  disconnect() {
    if (typeof window.bootstrap === 'undefined') return

    this.element.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      const instance = window.bootstrap.Tooltip.getInstance(el)
      if (instance) instance.dispose()
    })

    this.element.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
      const instance = window.bootstrap.Popover.getInstance(el)
      if (instance) instance.dispose()
    })
  }

  initializeBootstrap() {
    if (typeof window.bootstrap === 'undefined') return

    // Tooltips
    this.element.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      if (!window.bootstrap.Tooltip.getInstance(el)) {
        new window.bootstrap.Tooltip(el)
      }
    })

    // Popovers
    this.element.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
      if (!window.bootstrap.Popover.getInstance(el)) {
        new window.bootstrap.Popover(el)
      }
    })

    // Dropdowns
    this.element.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(el => {
      if (!window.bootstrap.Dropdown.getInstance(el)) {
        new window.bootstrap.Dropdown(el)
      }
    })
  }
}