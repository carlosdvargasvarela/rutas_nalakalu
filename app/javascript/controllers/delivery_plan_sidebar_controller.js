import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["list", "summary", "hiddenInputs", "submit"];

  connect() {
    const stored = sessionStorage.getItem("selectedDeliveries");
    this.selected = stored ? new Map(JSON.parse(stored)) : new Map();
    this.refresh();
    this.syncCheckboxes();
  }

  disconnect() {
    // Limpiar al salir de la página de creación
    if (!window.location.pathname.includes("/new")) {
      sessionStorage.removeItem("selectedDeliveries");
    }
  }

  syncCheckboxes() {
    document.querySelectorAll(".delivery-checkbox").forEach((cb) => {
      cb.checked = this.selected.has(cb.value);
    });
    const allChecked = document.querySelectorAll(".delivery-checkbox");
    const selectAll = document.querySelector("[data-action*='toggleAll']");
    if (selectAll && allChecked.length > 0) {
      selectAll.checked = [...allChecked].every((cb) => cb.checked);
    }
  }

  toggle(event) {
    const cb = event.target;
    const id = cb.value;
    const label = cb.dataset.label || `Entrega #${id}`;

    cb.checked ? this.selected.set(id, label) : this.selected.delete(id);
    this.persist();
    this.refresh();
  }

  toggleAll(event) {
    const master = event.target;
    document.querySelectorAll(".delivery-checkbox").forEach((cb) => {
      cb.checked = master.checked;
      const id = cb.value;
      const label = cb.dataset.label || `Entrega #${id}`;
      master.checked ? this.selected.set(id, label) : this.selected.delete(id);
    });
    this.persist();
    this.refresh();
  }

  persist() {
    sessionStorage.setItem(
      "selectedDeliveries",
      JSON.stringify([...this.selected]),
    );
  }

  refresh() {
    // Lista visual
    if (this.selected.size === 0) {
      this.listTarget.innerHTML = `
        <li class="list-group-item py-5 text-center text-muted">
          <i class="bi bi-plus-circle d-block h2 mb-2 opacity-25"></i>
          <p class="mb-0 fw-medium">Haz clic en los pedidos<br>para agregarlos aquí</p>
        </li>`;
    } else {
      this.listTarget.innerHTML = "";
      this.selected.forEach((label, id) => {
        const li = document.createElement("li");
        li.className =
          "list-group-item d-flex justify-content-between align-items-center py-2 px-3";
        li.innerHTML = `
          <span class="small fw-medium text-truncate me-2">${label}</span>
          <button type="button"
                  class="btn btn-sm btn-outline-danger border-0 p-0 px-1"
                  data-id="${id}">
            <i class="bi bi-x"></i>
          </button>`;
        li.querySelector("button").addEventListener("click", () => {
          this.selected.delete(id);
          const cb = document.querySelector(
            `.delivery-checkbox[value="${id}"]`,
          );
          if (cb) cb.checked = false;
          this.persist();
          this.refresh();
        });
        this.listTarget.appendChild(li);
      });
    }

    // Hidden inputs
    this.hiddenInputsTarget.innerHTML = "";
    this.selected.forEach((_label, id) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "delivery_ids[]";
      input.value = id;
      this.hiddenInputsTarget.appendChild(input);
    });

    // Resumen y submit
    const count = this.selected.size;
    this.summaryTarget.textContent = count;
    this.submitTarget.disabled = count === 0;
  }
}
