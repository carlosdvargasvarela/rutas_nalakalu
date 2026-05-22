// app/javascript/controllers/driver_assignment_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    id: Number,
    url: String,
  }

  static targets = ["statusBadge", "actionsContainer", "notesTextarea", "failReasonTextarea"]

  connect() {
    this._selectedReason = null
  }

  // ── Marcar como entregado ───────────────────────────────
  async complete(event) {
    event.preventDefault()
    this.setLoading(true)
    try {
      const response = await fetch(`${this.urlValue}/complete`, {
        method: "PATCH",
        headers: this._headers(),
      })
      const data = await response.json()
      if (response.ok) {
        this._markCompleted()
        this._dispatchProgress(data.progress)
        this._toast("Entrega completada ✓", "success")
      } else {
        this._toast(data.error || "Error al completar", "error")
      }
    } catch {
      this._toast("Sin conexión. Intenta de nuevo.", "warning")
    } finally {
      this.setLoading(false)
    }
  }

  // ── Abrir modal de nota ─────────────────────────────────
  openNoteModal(event) {
    event.preventDefault()
    const modalEl = this.element.querySelector(`#notaModal${this.idValue}`)
    if (modalEl) new bootstrap.Modal(modalEl).show()
  }

  // ── Abrir modal de fallo ────────────────────────────────
  openFailModal(event) {
    event.preventDefault()
    this._selectedReason = null

    // Reset reason buttons dentro del controller element
    this.element.querySelectorAll(".fail-reason-btn").forEach(btn => {
      btn.classList.remove("selected")
    })

    // Limpiar textarea de razón personalizada
    if (this.hasFailReasonTextareaTarget) {
      this.failReasonTextareaTarget.value = ""
    }

    const modalEl = this.element.querySelector(`#failModal${this.idValue}`)
    if (modalEl) new bootstrap.Modal(modalEl).show()
  }

  // ── Seleccionar razón predefinida ───────────────────────
  selectReason(event) {
    const btn = event.currentTarget
    this._selectedReason = btn.dataset.reason

    this.element.querySelectorAll(".fail-reason-btn").forEach(b => {
      b.classList.remove("selected")
    })
    btn.classList.add("selected")

    // Limpiar textarea para que la razón predefinida tenga prioridad
    if (this.hasFailReasonTextareaTarget) {
      this.failReasonTextareaTarget.value = ""
    }
  }

  // ── Confirmar fallo ─────────────────────────────────────
  async confirmFail(event) {
    event.preventDefault()

    const customReason = this.hasFailReasonTextareaTarget
      ? this.failReasonTextareaTarget.value.trim()
      : ""
    const reason = customReason || this._selectedReason || "No especificado"

    // Cerrar modal
    const modalEl = this.element.querySelector(`#failModal${this.idValue}`)
    if (modalEl) bootstrap.Modal.getInstance(modalEl)?.hide()

    this.setLoading(true)
    try {
      const response = await fetch(`${this.urlValue}/fail`, {
        method: "PATCH",
        headers: this._headers(),
        body: JSON.stringify({ reason }),
      })
      const data = await response.json()
      if (response.ok) {
        this._markFailed()
        this._dispatchProgress(data.progress)
        this._toast("Marcado como no entregado. Se reagendará en 7 días.", "warning")
      } else {
        this._toast(data.error || "Error al procesar", "error")
      }
    } catch {
      this._toast("Sin conexión. Intenta de nuevo.", "warning")
    } finally {
      this.setLoading(false)
    }
  }

  // ── Guardar nota ────────────────────────────────────────
  async saveNote(event) {
    event.preventDefault()
    if (!this.hasNotesTextareaTarget) return
    const note = this.notesTextareaTarget.value.trim()
    if (!note) return
    try {
      const response = await fetch(`${this.urlValue}/add_note`, {
        method: "PATCH",
        headers: this._headers(),
        body: JSON.stringify({ note }),
      })
      if (response.ok) {
        this._toast("Nota guardada", "success")
      } else {
        this._toast("Error al guardar nota", "error")
      }
    } catch {
      this._toast("Sin conexión", "warning")
    }
  }

  // ── Helpers ─────────────────────────────────────────────
  setLoading(isLoading) {
    this.element.style.opacity = isLoading ? "0.6" : "1"
    this.element.style.pointerEvents = isLoading ? "none" : "auto"
  }

  _markCompleted() {
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "Completado"
      this.statusBadgeTarget.className = "dk-pill dk-pill-success"
    }
    // Actualizar borde del card
    this.element.dataset.status = "completed"
    const stopNum = this.element.querySelector(".dk-stop-num")
    if (stopNum) stopNum.dataset.status = "completed"

    if (this.hasActionsContainerTarget) {
      this.actionsContainerTarget.innerHTML = `
        <div class="dk-delivered-state">
          <i class="bi bi-check-circle-fill" style="font-size:1.8rem;"></i>
          <span>Entrega completada</span>
        </div>`
    }
  }

  _markFailed() {
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "No entregado"
      this.statusBadgeTarget.className = "dk-pill dk-pill-danger"
    }
    this.element.dataset.status = "cancelled"
    const stopNum = this.element.querySelector(".dk-stop-num")
    if (stopNum) stopNum.dataset.status = "cancelled"

    if (this.hasActionsContainerTarget) {
      this.actionsContainerTarget.innerHTML = `
        <div class="dk-failed-state">
          <i class="bi bi-x-circle-fill" style="font-size:1.8rem;"></i>
          <span>No se pudo entregar – reagendado en 7 días</span>
        </div>`
    }
  }

  _dispatchProgress(progress) {
    if (!progress) return
    document.dispatchEvent(new CustomEvent("driver:assignment:updated", { detail: { progress } }))
  }

  _headers() {
    return {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
    }
  }

  _toast(message, type = "info") {
    document.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type } }))
  }
}
