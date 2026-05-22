// app/javascript/controllers/delivery_item_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["badge", "buttons", "notePreview"]
  static values  = {
    itemId:      Number,
    deliveryId:  Number,
    status:      String,
    note:        String,
    product:     String,
    saveNoteUrl: String,
  }

  connect() {}

  async markLoaded(event) {
    event.preventDefault()
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("loaded")
        this._dispatchUpdate("loaded")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  async markUnloaded(event) {
    event.preventDefault()
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("unloaded")
        this._dispatchUpdate("unloaded")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  async markMissing(event) {
    event.preventDefault()
    // Sin confirm() — el botón ↺ Desmarcar sirve como undo
    this._setLoading()
    try {
      const response = await this._submit(event.currentTarget.href, "POST")
      if (response.ok) {
        this._applyStatus("missing")
        this._dispatchUpdate("missing")
      } else {
        this._setError()
      }
    } catch {
      this._setError()
    }
  }

  openNoteSheet(event) {
    event.preventDefault()
    document.dispatchEvent(new CustomEvent("delivery-item:open-note-sheet", {
      detail: {
        itemId:     this.itemIdValue,
        product:    this.productValue,
        note:       this.noteValue,
        saveUrl:    this.saveNoteUrlValue,
        controller: this,
      }
    }))
  }

  // Llamado por note_sheet_controller tras guardar exitosamente
  noteUpdated(newNote) {
    this.noteValue = newNote
    if (this.hasNotePreviewTarget) {
      if (newNote.trim()) {
        this.notePreviewTarget.innerHTML =
          `<i class="bi bi-chat-left-text me-1"></i>${this._escapeHtml(newNote.substring(0, 50))}${newNote.length > 50 ? "…" : ""}`
        this.notePreviewTarget.style.display = ""
      } else {
        this.notePreviewTarget.textContent = ""
        this.notePreviewTarget.style.display = "none"
      }
    }
    const noteBtn = this.element.querySelector("[data-action*='openNoteSheet']")
    if (noteBtn) {
      noteBtn.classList.toggle("pd-btn-note--active", newNote.trim().length > 0)
    }
  }

  // ── Privados ──

  async _submit(url, method) {
    const csrfToken = document.querySelector("[name='csrf-token']").content
    const response = await fetch(url, {
      method,
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      },
      credentials: "same-origin",
    })
    const contentType = response.headers.get("Content-Type") || ""
    if (contentType.includes("turbo-stream")) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    }
    return response
  }

  _setLoading() {
    this._disableButtons()
    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML =
        '<span class="spinner-border spinner-border-sm me-1"></span>'
      this.badgeTarget.className = "pd-badge pd-badge--pending"
    }
  }

  _applyStatus(status) {
    this.statusValue = status
    this._enableButtons()
    this._updateBadge(status)
    this._updateRowBackground(status)
    this.element.classList.add("pd-flash-success")
    setTimeout(() => this.element.classList.remove("pd-flash-success"), 600)
  }

  _setError() {
    this._enableButtons()
    if (this.hasBadgeTarget) {
      this.badgeTarget.innerHTML = '<i class="bi bi-exclamation-circle me-1"></i>Error'
      this.badgeTarget.className = "pd-badge pd-badge--missing"
    }
    this.element.classList.add("pd-flash-error")
    setTimeout(() => {
      this.element.classList.remove("pd-flash-error")
      this._updateBadge(this.statusValue)
    }, 2000)
  }

  _updateBadge(status) {
    if (!this.hasBadgeTarget) return
    const configs = {
      loaded:  { cls: "pd-badge pd-badge--ok",     html: "<i class='bi bi-check-circle-fill me-1'></i>Cargado"                   },
      missing: { cls: "pd-badge pd-badge--missing", html: "<i class='bi bi-exclamation-triangle-fill me-1'></i>Faltante"          },
      unloaded:{ cls: "pd-badge",                   html: "" },
    }
    const cfg = configs[status] || configs.unloaded
    this.badgeTarget.className = cfg.cls
    this.badgeTarget.innerHTML = cfg.html
  }

  _updateRowBackground(status) {
    this.element.classList.remove("pd-item-row--loaded", "pd-item-row--missing")
    if (status === "loaded")  this.element.classList.add("pd-item-row--loaded")
    if (status === "missing") this.element.classList.add("pd-item-row--missing")
  }

  _disableButtons() {
    if (this.hasButtonsTarget) {
      this.buttonsTarget.querySelectorAll("a, button").forEach(el => {
        el.classList.add("disabled")
        el.setAttribute("aria-disabled", "true")
      })
    }
  }

  _enableButtons() {
    if (this.hasButtonsTarget) {
      this.buttonsTarget.querySelectorAll("a, button").forEach(el => {
        el.classList.remove("disabled")
        el.removeAttribute("aria-disabled")
      })
    }
  }

  _dispatchUpdate(status) {
    this.element.dispatchEvent(new CustomEvent("delivery-item:updated", {
      detail: { itemId: this.itemIdValue, deliveryId: this.deliveryIdValue, status },
      bubbles: true,
    }))
  }

  _escapeHtml(str) {
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
