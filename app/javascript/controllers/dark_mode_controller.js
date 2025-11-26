import { Controller } from "@hotwired/stimulus"

// Conecta este controller al HTML con: data-controller="dark-mode"
export default class extends Controller {
  static targets = ["toggle", "label"]

  connect() {
    // Cargar preferencia guardada
    const savedMode = localStorage.getItem('darkMode')

    if (savedMode === 'enabled') {
      this.enableDarkMode()
    } else {
      // Por defecto, usar modo claro (desactivado)
      // Si no hay preferencia guardada o está explícitamente deshabilitado
      this.disableDarkMode()
    }

    // Sincronizar el estado del toggle y label
    this.syncToggle()
    this.updateLabel()
  }

  toggle() {
    if (document.body.classList.contains('dark-mode')) {
      this.disableDarkMode()
    } else {
      this.enableDarkMode()
    }

    this.syncToggle()
    this.updateLabel()
  }

  enableDarkMode() {
    document.body.classList.add('dark-mode')
    localStorage.setItem('darkMode', 'enabled')

    // Emitir evento personalizado para que otros componentes puedan reaccionar
    document.dispatchEvent(new CustomEvent('darkModeEnabled'))
  }

  disableDarkMode() {
    document.body.classList.remove('dark-mode')
    localStorage.setItem('darkMode', 'disabled')

    // Emitir evento personalizado
    document.dispatchEvent(new CustomEvent('darkModeDisabled'))
  }

  syncToggle() {
    if (this.hasToggleTarget) {
      const isDark = document.body.classList.contains('dark-mode')
      this.toggleTarget.checked = isDark
    }
  }

  updateLabel() {
    if (this.hasLabelTarget) {
      const isDark = document.body.classList.contains('dark-mode')
      this.labelTarget.textContent = isDark ? 'Modo claro' : 'Modo oscuro'
    }
  }
}
