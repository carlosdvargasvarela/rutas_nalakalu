// app/javascript/controllers/delivery_split_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["datesList", "headerRow", "tableBody", "addDateBtn", "summaryText"];
  static values = {
    minDate: String,
    maxCols: { type: Number, default: 8 },
    existingDeliveries: { type: Array, default: [] },
  };

  connect() {
    this._addColumn();
    this._addColumn();
  }

  // ─── Acciones públicas (data-action) ─────────────────────────────────────────

  addColumn() {
    this._addColumn();
  }

  removeColumn(event) {
    const chip = event.currentTarget.closest('[data-role="date-chip"]');
    if (!chip) return;

    const colIdx = chip.dataset.colIdx;

    chip.remove();
    this.headerRowTarget.querySelector(`th[data-col-idx="${colIdx}"]`)?.remove();
    this.tableBodyTarget.querySelectorAll(`td[data-col-idx="${colIdx}"]`).forEach((td) => td.remove());

    this._renumber();
    this._recalculateAll();
  }

  dateChanged(event) {
    this._syncHeaderLabel(event.currentTarget);
  }

  quantityChanged(event) {
    this._recalculateRow(event.currentTarget.closest("tr"));
    this._updateSummary();
  }

  validateBeforeSubmit(event) {
    // Verificar que no haya filas con saldo negativo
    let hasNegative = false;
    this.tableBodyTarget.querySelectorAll("tr").forEach((row) => {
      const original = parseInt(row.dataset.originalQty, 10);
      const inputs = [...row.querySelectorAll('input[type="number"]')];
      const total = inputs.reduce((s, i) => s + (parseInt(i.value, 10) || 0), 0);
      if (total > original) hasNegative = true;
    });

    if (hasNegative) {
      event.preventDefault();
      alert("Hay productos con más unidades asignadas de las disponibles (marcados en rojo). Corregí las cantidades antes de continuar.");
      return;
    }

    // Verificar que al menos una fecha tenga valor
    const anyDate = [...this.datesListTarget.querySelectorAll('input[type="date"]')].some(
      (i) => i.value
    );
    if (!anyDate) {
      event.preventDefault();
      alert("Debés ingresar al menos una fecha destino.");
    }
  }

  // ─── Privados ─────────────────────────────────────────────────────────────────

  _addColumn() {
    const currentCount = this.datesListTarget.querySelectorAll('[data-role="date-chip"]').length;
    if (currentCount >= this.maxColsValue) return;

    // El índice real se asigna en _renumber; usamos currentCount como provisional
    const idx = currentCount;

    // ── Chip de fecha ──
    const chip = document.createElement("div");
    chip.dataset.role = "date-chip";
    chip.dataset.colIdx = idx;
    chip.className = "d-flex align-items-center gap-1 border rounded px-2 py-1 bg-white shadow-sm";
    chip.innerHTML = `
      <span class="chip-label text-muted small fw-bold" style="white-space:nowrap;">Entrega ${idx + 1}:</span>
      <input type="date"
             name="target_dates[]"
             class="form-control form-control-sm border-0 p-0 ps-1"
             style="width:145px;"
             min="${this.minDateValue}"
             data-col-idx="${idx}"
             data-action="change->delivery-split#dateChanged"
             required>
      <button type="button"
              class="btn-close btn-sm"
              style="font-size:0.6rem;"
              title="Quitar fecha"
              data-action="click->delivery-split#removeColumn"></button>
    `;
    this.datesListTarget.appendChild(chip);

    // ── Encabezado en la tabla ──
    const remainingTh = this.headerRowTarget.querySelector('th[data-role="remaining-th"]');
    const th = document.createElement("th");
    th.dataset.role = "date-th";
    th.dataset.colIdx = idx;
    th.className = "text-center py-1";
    th.style.cssText = "width:100px; font-size:0.7rem; text-transform:uppercase;";
    th.innerHTML = `<span class="date-header-label text-muted" data-col-idx="${idx}">Entrega ${idx + 1}</span>`;
    this.headerRowTarget.insertBefore(th, remainingTh);

    // ── Celda de cantidad en cada fila ──
    this.tableBodyTarget.querySelectorAll("tr").forEach((row) => {
      const itemId = row.dataset.itemId;
      const remainTd = row.querySelector('td[data-role="remaining-td"]');
      const td = document.createElement("td");
      td.dataset.role = "qty-td";
      td.dataset.colIdx = idx;
      td.className = "text-center py-1";
      td.innerHTML = `
        <input type="number"
               name="splits[${itemId}][${idx}]"
               class="form-control form-control-sm text-center p-1"
               style="width:70px; margin:auto;"
               min="0"
               value=""
               data-item-id="${itemId}"
               data-col-idx="${idx}"
               data-action="input->delivery-split#quantityChanged"
               placeholder="0">
      `;
      row.insertBefore(td, remainTd);
    });

    this._renumber();
    this._recalculateAll();
  }

  // Renumera secuencialmente todos los chips, th y td en orden DOM
  _renumber() {
    const chips = [...this.datesListTarget.querySelectorAll('[data-role="date-chip"]')];
    const headerThs = [...this.headerRowTarget.querySelectorAll('th[data-role="date-th"]')];

    chips.forEach((chip, i) => {
      chip.dataset.colIdx = i;

      const label = chip.querySelector(".chip-label");
      if (label) label.textContent = `Entrega ${i + 1}:`;

      const dateInput = chip.querySelector('input[type="date"]');
      if (dateInput) {
        dateInput.dataset.colIdx = i;
        this._syncHeaderLabel(dateInput, i, headerThs[i]);
      }

      const th = headerThs[i];
      if (th) {
        th.dataset.colIdx = i;
        const thLabel = th.querySelector(".date-header-label");
        if (thLabel) thLabel.dataset.colIdx = i;
      }
    });

    // Renumerar celdas de cantidad
    this.tableBodyTarget.querySelectorAll("tr").forEach((row) => {
      const itemId = row.dataset.itemId;
      row.querySelectorAll('td[data-role="qty-td"]').forEach((td, i) => {
        td.dataset.colIdx = i;
        const input = td.querySelector("input");
        if (input) {
          input.name = `splits[${itemId}][${i}]`;
          input.dataset.colIdx = i;
        }
      });
    });

    this._updateAddButton();
  }

  _syncHeaderLabel(dateInput, colIdx = null, th = null) {
    const idx = colIdx ?? parseInt(dateInput.dataset.colIdx, 10);
    const headerTh = th ?? this.headerRowTarget.querySelector(`th[data-col-idx="${idx}"]`);
    const label = headerTh?.querySelector(".date-header-label");
    if (!label) return;

    if (!dateInput.value) {
      label.textContent = `Entrega ${idx + 1}`;
      return;
    }

    const d = new Date(dateInput.value + "T00:00:00");
    const formatted = d.toLocaleDateString("es-CR", {
      day: "2-digit",
      month: "2-digit",
      year: "2-digit",
    });

    const existing = this.existingDeliveriesValue.find((e) => e.date === dateInput.value);
    if (existing) {
      label.innerHTML = `${formatted}&nbsp;<span class="badge bg-info text-dark" style="font-size:0.55rem;" title="Ya existe una entrega ese día. Los productos se sumarán a ella.">+existente</span>`;
    } else {
      label.textContent = formatted;
    }
  }

  _recalculateAll() {
    this.tableBodyTarget.querySelectorAll("tr").forEach((row) => this._recalculateRow(row));
    this._updateSummary();
  }

  _recalculateRow(row) {
    const original = parseInt(row.dataset.originalQty, 10);
    const inputs = [...row.querySelectorAll('input[type="number"]')];
    const total = inputs.reduce((sum, inp) => sum + (parseInt(inp.value, 10) || 0), 0);
    const remaining = original - total;

    const badge = row.querySelector(".remaining-badge");
    const cell = row.querySelector('td[data-role="remaining-td"]');
    if (!badge || !cell) return;

    badge.textContent = remaining;
    cell.classList.remove("table-warning", "table-success", "table-danger");
    badge.classList.remove("text-dark", "text-success", "text-danger");

    if (remaining < 0) {
      cell.classList.add("table-danger");
      badge.classList.add("text-danger", "fw-bold");
    } else if (remaining === 0) {
      cell.classList.add("table-success");
      badge.classList.add("text-success", "fw-bold");
    } else {
      cell.classList.add("table-warning");
      badge.classList.add("text-dark", "fw-bold");
    }
  }

  _updateSummary() {
    const total = [...this.tableBodyTarget.querySelectorAll('input[type="number"]')].reduce(
      (s, i) => s + (parseInt(i.value, 10) || 0),
      0
    );
    if (this.hasSummaryTextTarget) {
      this.summaryTextTarget.textContent =
        total > 0 ? `${total} unidades asignadas para mover.` : "";
    }
  }

  _updateAddButton() {
    const count = this.datesListTarget.querySelectorAll('[data-role="date-chip"]').length;
    this.addDateBtnTarget.disabled = count >= this.maxColsValue;
  }
}
