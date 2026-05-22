// app/javascript/controllers/note_sheet_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets  = ["textarea", "productLabel"]
  static values   = { saveUrl: String }

  connect() {
    this._activeItemController = null
    this._onOpenBound = this._onOpen.bind(this)
    document.addEventListener("delivery-item:open-note-sheet", this._onOpenBound)
  }

  disconnect() {
    document.removeEventListener("delivery-item:open-note-sheet", this._onOpenBound)
  }

  close() {
    this.element.classList.remove("pd-sheet-open")
    this._activeItemController = null
  }

  async save() {
    const note      = this.textareaTarget.value.trim()
    const saveUrl   = this.saveUrlValue
    const csrfToken = document.querySelector("[name='csrf-token']").content

    const saveBtn = this.element.querySelector(".pd-sheet-save")
    if (saveBtn) {
      saveBtn.disabled = true
      saveBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>Guardando...'
    }

    try {
      const response = await fetch(saveUrl, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token":  csrfToken,
          "Content-Type":  "application/x-www-form-urlencoded",
          "Accept":        "text/vnd.turbo-stream.html",
        },
        credentials: "same-origin",
        body: new URLSearchParams({ note }),
      })

      const contentType = response.headers.get("Content-Type") || ""
      if (response.ok) {
        if (contentType.includes("turbo-stream")) {
          const html = await response.text()
          Turbo.renderStreamMessage(html)
        }
        if (this._activeItemController) {
          this._activeItemController.noteUpdated(note)
        }
        this.close()
      } else {
        this._showSaveError(saveBtn)
      }
    } catch {
      this._showSaveError(saveBtn)
    }
  }

  // -- Privados --

  _onOpen(event) {
    const { product, note, saveUrl, controller } = event.detail
    this._activeItemController = controller
    this.saveUrlValue = saveUrl

    if (this.hasProductLabelTarget) {
      this.productLabelTarget.textContent = product || "Producto"
    }
    if (this.hasTextareaTarget) {
      this.textareaTarget.value = note || ""
      setTimeout(() => this.textareaTarget.focus(), 260)
    }

    this.element.classList.add("pd-sheet-open")

    const saveBtn = this.element.querySelector(".pd-sheet-save")
    if (saveBtn) {
      saveBtn.disabled = false
      saveBtn.innerHTML = '<i class="bi bi-floppy me-1"></i>Guardar nota'
    }
  }

  _showSaveError(saveBtn) {
    if (saveBtn) {
      saveBtn.disabled = false
      saveBtn.innerHTML = '<i class="bi bi-exclamation-circle me-1"></i>Error — Reintentar'
      saveBtn.style.background = "linear-gradient(135deg,#7f1d1d,#b91c1c)"
      saveBtn.style.color = "#fca5a5"
    }
  }
}
