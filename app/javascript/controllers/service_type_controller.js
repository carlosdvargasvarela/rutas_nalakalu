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
    "btnReparacion",
    "recoleccionFields",
    "devolucionSection",
    "reparacionSection",
    "footerHint",
    "btnRepairRecoleccion",
    "btnRepairEntrega",
    "repairPickupFields",
    "repairReturnSection",
  ];

  // Fallback solo por si una vista olvida pasar data-service-type-labels-value;
  // la fuente real es config/deliveries_vocabulary.yml vía Deliveries::Vocabulary.
  static values = {
    labels: {
      type: Object,
      default: {
        recoleccion: { label: "Recolección" },
        devolucion: { label: "Devolución" },
        reparacion: { label: "Reparación en sitio" },
        retiro: { label: "Retiro" },
        entrega: { label: "Entrega" },
      },
    },
  };

  _label(key) {
    return this.labelsValue[key]?.label ?? key;
  }

  // ─── Legacy action (full forms: only updates the notice) ───────────────────
  updateNotice(event) {
    this._updateNotice(event.target.value);
  }

  // ─── Modal workspace: mode selection ──────────────────────────────────────

  selectRecoleccion() {
    this._setMode("recoleccion");

    this.btnRecoleccionTarget.classList.replace("btn-outline-secondary", "btn-warning");
    this.btnDevolucionTarget.classList.replace("btn-warning", "btn-outline-secondary");
    if (this.hasBtnReparacionTarget) {
      this.btnReparacionTarget.classList.replace("btn-warning", "btn-outline-secondary");
    }

    this.recoleccionFieldsTarget.disabled = false;
    this.recoleccionFieldsTarget.classList.remove("d-none");

    if (this.hasDevolucionSectionTarget) {
      this.devolucionSectionTarget.classList.add("d-none");
    }
    if (this.hasReparacionSectionTarget) {
      this.reparacionSectionTarget.classList.add("d-none");
    }

    this._showNotes();
    this._fillNotes("recoleccion");
    this._showSubmit();

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Agendar devolución";
    }
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-calendar-event me-1"></i>La fecha indicada es para la devolución futura del producto.';
    }
  }

  selectDevolucion() {
    this._setMode("devolucion");

    this.btnDevolucionTarget.classList.replace("btn-outline-secondary", "btn-warning");
    this.btnRecoleccionTarget.classList.replace("btn-warning", "btn-outline-secondary");
    if (this.hasBtnReparacionTarget) {
      this.btnReparacionTarget.classList.replace("btn-warning", "btn-outline-secondary");
    }

    if (this.hasRecoleccionFieldsTarget) {
      this.recoleccionFieldsTarget.disabled = true;
      this.recoleccionFieldsTarget.classList.add("d-none");
    }
    if (this.hasDevolucionSectionTarget) {
      this.devolucionSectionTarget.classList.remove("d-none");
    }
    if (this.hasReparacionSectionTarget) {
      this.reparacionSectionTarget.classList.add("d-none");
    }

    this._showNotes();
    this._fillNotes("devolucion");
    this._showSubmit();

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Registrar nota";
    }
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-info-circle me-1"></i>Solo se registrará una nota. No se crea ninguna entrega adicional.';
    }
  }

  selectReparacion() {
    this._setMode("reparacion");

    this.btnReparacionTarget.classList.replace("btn-outline-secondary", "btn-warning");
    this.btnRecoleccionTarget.classList.replace("btn-warning", "btn-outline-secondary");
    this.btnDevolucionTarget.classList.replace("btn-warning", "btn-outline-secondary");

    if (this.hasRecoleccionFieldsTarget) {
      this.recoleccionFieldsTarget.disabled = true;
      this.recoleccionFieldsTarget.classList.add("d-none");
    }
    if (this.hasDevolucionSectionTarget) {
      this.devolucionSectionTarget.classList.add("d-none");
    }
    if (this.hasReparacionSectionTarget) {
      this.reparacionSectionTarget.classList.remove("d-none");
    }

    this._showNotes();
    this._fillNotes("reparacion");
    this._showSubmit();

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Registrar reparación";
    }
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-wrench me-1"></i>Solo se registrará una nota. No se crea ninguna entrega adicional.';
    }
  }

  // ─── Modal workspace: repair service mode selection ───────────────────────

  selectRepairRecoleccion() {
    this._setMode("repair_recoleccion");

    this.btnRepairRecoleccionTarget.classList.replace("btn-outline-secondary", "btn-info");
    this.btnRepairEntregaTarget.classList.replace("btn-info", "btn-outline-secondary");

    this.repairPickupFieldsTarget.disabled = false;
    this.repairPickupFieldsTarget.classList.remove("d-none");

    if (this.hasRepairReturnSectionTarget) {
      this.repairReturnSectionTarget.classList.add("d-none");
    }

    this._showNotes();
    this._fillRepairNotes("repair_recoleccion");
    this._showSubmit();

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Agendar devolución de reparación";
    }
    if (this.hasFooterHintTarget) {
      this.footerHintTarget.innerHTML =
        '<i class="bi bi-calendar-event me-1"></i>La fecha indicada es para la devolución del producto reparado al cliente.';
    }
  }

  selectRepairEntrega() {
    this._setMode("repair_entrega");

    this.btnRepairEntregaTarget.classList.replace("btn-outline-secondary", "btn-info");
    this.btnRepairRecoleccionTarget.classList.replace("btn-info", "btn-outline-secondary");

    if (this.hasRepairPickupFieldsTarget) {
      this.repairPickupFieldsTarget.disabled = true;
      this.repairPickupFieldsTarget.classList.add("d-none");
    }
    if (this.hasRepairReturnSectionTarget) {
      this.repairReturnSectionTarget.classList.remove("d-none");
    }

    this._showNotes();
    this._fillRepairNotes("repair_entrega");
    this._showSubmit();

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = "Registrar nota";
    }
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
      this.notesTarget.value = `${this._label("devolucion")} al cliente ${hint}`.trim();
    } else if (mode === "reparacion") {
      this.notesTarget.value = `${this._label("reparacion")} ${hint}`.trim();
    } else {
      this.notesTarget.value = `${this._label("recoleccion")} ${hint}`.trim();
    }
  }

  _showSubmit() {
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.classList.remove("d-none");
    }
  }

  _fillRepairNotes(mode) {
    if (!this.hasNotesTarget) return;
    if (this.notesTarget.value.trim()) return;
    const hint = document.getElementById("rs_product_hint")?.value || "";
    this.notesTarget.value = (mode === "repair_entrega"
      ? `${this._label("entrega")} de producto reparado ${hint}`
      : `${this._label("retiro")} para reparación ${hint}`
    ).trim();
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
      repair_with_return: `<i class="bi bi-arrow-return-right me-1 text-info"></i>
        Se crearán <strong>dos gestiones</strong>: Recolección para reparación en la fecha indicada
        y Devolución automáticamente <strong>+15 días</strong> después.`,
      repair_pickup: `<i class="bi bi-wrench-adjustable me-1 text-secondary"></i>
        Solo se registrará la <strong>Recolección del producto</strong> para reparación.`,
      repair_return: `<i class="bi bi-wrench-adjustable-circle me-1 text-secondary"></i>
        Solo se registrará la <strong>Devolución del producto reparado</strong> al cliente.`,
      "": `<i class="bi bi-info-circle me-1 text-muted"></i>
        Seleccioná el tipo para ver los detalles.`,
    };
    this.noticeTarget.innerHTML = messages[type] || messages[""];
  }
}
