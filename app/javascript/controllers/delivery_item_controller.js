// app/javascript/controllers/delivery_item_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notePreview"]
  static values  = {
    itemId:      Number,
    deliveryId:  Number,
    note:        String,
    product:     String,
    saveNoteUrl: String,
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

  _escapeHtml(str) {
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
