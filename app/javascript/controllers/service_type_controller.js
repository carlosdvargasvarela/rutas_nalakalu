import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "notice",
    "notes",
    "notesSection",
    "submitLabel",
    "submitBtn",
    "modeInput",
    "btnRecoleccion",
    "btnDevolucion",
    "recoleccionFields",
    "devolucionSection",
    "footerHint",
  ];

  // ─── Legacy action (full forms: only updates the notice) ───────────────────
  updateNotice(event) {
    this._updateNotice(event.target.value);
  }

  // ─── Modal workspace: mode selection ──────────────────────────────────────

  selectRecoleccion() {
    this._setMode("recoleccion");

    // Activate button styles
    this.btnRecoleccionTarget.classList.replace("btn-outline-secondary", "btn-warning");
    this.btnDevolucionTarget.classList.replace("btn-warning", "btn-outline-secondary");

    // Show recolección section (enable fieldset)
    this.recoleccionFieldsTarget.disabled = false;
    this.recoleccionFieldsTarget.classList.remove("d-none");

    // Hide devolución info
    if (this.hasDevolucionSectionTarget) {
      this.devolucionSectionTarget.classList.add("d-none");
    }

    // Show notes + autofill if empty
    this._showNotes();
    this._fillNotes("recoleccion");

    // Update submit
    this._showSubmit();
    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Agendar devolución";
    }

    // Update footer hint
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-calendar-event me-1"></i>La fecha indicada es para la devolución futura del producto.';
    }
  }

  selectDevolucion() {
    this._setMode("devolucion");

    // Activate button styles
    this.btnDevolucionTarget.classList.replace("btn-outline-secondary", "btn-warning");
    this.btnRecoleccionTarget.classList.replace("btn-warning", "btn-outline-secondary");

    // Disable and hide recolección section
    if (this.hasRecoleccionFieldsTarget) {
      this.recoleccionFieldsTarget.disabled = true;
      this.recoleccionFieldsTarget.classList.add("d-none");
    }

    // Show devolución info alert
    if (this.hasDevolucionSectionTarget) {
      this.devolucionSectionTarget.classList.remove("d-none");
    }

    // Show notes + autofill if empty
    this._showNotes();
    this._fillNotes("devolucion");

    // Update submit
    this._showSubmit();
    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Registrar nota";
    }

    // Update footer hint
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-info-circle me-1"></i>Solo se registrará una nota. No se crea ninguna entrega adicional.';
    }
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  _setMode(mode) {
    if (this.hasModeInputTarget) {
      this.modeInputTarget.value = mode;
    }
  }

  _showNotes() {
    if (this.hasNotesSectionTarget) {
      this.notesSectionTarget.classList.remove("d-none");
    }
  }

  _fillNotes(mode) {
    if (!this.hasNotesTarget) return;
    if (this.notesTarget.value.trim()) return; // don't overwrite user-typed content
    const hint = document.getElementById("sc_product_hint")?.value || "";
    if (mode === "devolucion") {
      this.notesTarget.value = `Devolución al cliente ${hint}`.trim();
    } else {
      this.notesTarget.value = `Recolección ${hint}`.trim();
    }
  }

  _showSubmit() {
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.classList.remove("d-none");
    }
  }

  _updateNotice(type) {
    if (!this.hasNoticeTarget) return;
    const messages = {
      pickup_with_return: `<i class="bi bi-arrow-return-right me-1 text-warning"></i>
        Se crearán <strong>dos gestiones</strong>: Recolección en la fecha indicada
        y Devolución automáticamente <strong>+15 días</strong> después.`,
      only_pickup: `<i class="bi bi-truck me-1 text-secondary"></i>
        Solo se registrará la <strong>Recolección del producto</strong>.`,
      return_delivery: `<i class="bi bi-arrow-counterclockwise me-1 text-secondary"></i>
        Se registrará una <strong>Devolución al cliente</strong>.`,
      onsite_repair: `<i class="bi bi-wrench me-1 text-secondary"></i>
        Se registrará una <strong>Reparación en sitio</strong>.`,
      "": `<i class="bi bi-info-circle me-1 text-muted"></i>
        Seleccioná el tipo para ver los detalles.`,
    };
    this.noticeTarget.innerHTML = messages[type] || messages[""];
  }
}
