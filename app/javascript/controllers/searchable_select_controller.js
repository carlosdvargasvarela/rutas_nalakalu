// app/javascript/controllers/searchable_select_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    placeholder: { type: String, default: "Seleccionar..." },
    searchPlaceholder: { type: String, default: "Buscar..." },
    noResults: { type: String, default: "Sin resultados" },
  };

  connect() {
    this.selectElement =
      this.element.tagName === "SELECT"
        ? this.element
        : this.element.querySelector("select");

    if (!this.selectElement) {
      console.warn(
        "[searchable-select] No se encontró un <select> para inicializar.",
      );
      return;
    }

    if (this.initialized) return;

    this.initialized = true;
    this.build();
    this.bindEvents();
    this.syncFromSelect();

    // ← Exponer el controller en el elemento <select> para acceso externo
    this.selectElement.searchableSelectController = this;
  }

  disconnect() {
    this.unbindEvents();
    this.destroy();
    this.initialized = false;
  }

  // Método público para que otros controllers fuercen el re-render
  refreshFromSelect() {
    this.renderOptions();
    this.syncFromSelect();
  }

  // Compatibilidad con código que espera select.tomselect
  get tomselect() {
    return {
      clear: () => this.clearSelection(),
      clearOptions: () => {
        this.selectElement.innerHTML = "";
        this.renderOptions();
      },
      addOption: ({ value, text }) => {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = text;
        this.selectElement.appendChild(option);
        this.renderOptions();
      },
      refreshOptions: () => this.renderOptions(),
      disable: () => this.disable(),
      enable: () => this.enable(),
    };
  }

  build() {
    this.selectElement.style.display = "none";

    this.wrapper = document.createElement("div");
    this.wrapper.className = "ss-wrapper position-relative";

    this.trigger = document.createElement("button");
    this.trigger.type = "button";
    this.trigger.className =
      "ss-trigger form-select text-start d-flex align-items-center justify-content-between gap-2";
    this.trigger.setAttribute("aria-expanded", "false");
    this.trigger.setAttribute("aria-haspopup", "listbox");

    this.triggerText = document.createElement("span");
    this.triggerText.className =
      "ss-trigger-text text-truncate flex-grow-1 text-muted";
    this.triggerText.textContent = this.placeholderValue;

    this.clearBtn = document.createElement("button");
    this.clearBtn.type = "button";
    this.clearBtn.className = "ss-clear btn-close btn-sm flex-shrink-0";
    this.clearBtn.style.display = "none";
    this.clearBtn.setAttribute("aria-label", "Limpiar selección");

    this.trigger.appendChild(this.triggerText);
    this.trigger.appendChild(this.clearBtn);

    this.dropdown = document.createElement("div");
    this.dropdown.className = "ss-dropdown border rounded bg-white shadow-sm";
    this.dropdown.style.display = "none";
    this.dropdown.style.position = "absolute";
    this.dropdown.style.top = "calc(100% + 4px)";
    this.dropdown.style.left = "0";
    this.dropdown.style.right = "0";
    this.dropdown.style.zIndex = "1055";
    this.dropdown.style.maxHeight = "280px";
    this.dropdown.style.overflow = "hidden";

    this.searchInput = document.createElement("input");
    this.searchInput.type = "text";
    this.searchInput.className =
      "ss-search form-control form-control-sm border-0 border-bottom rounded-0";
    this.searchInput.placeholder = this.searchPlaceholderValue;
    this.searchInput.autocomplete = "off";

    this.list = document.createElement("ul");
    this.list.className = "ss-list list-unstyled mb-0 overflow-auto";
    this.list.style.maxHeight = "220px";
    this.list.setAttribute("role", "listbox");

    this.dropdown.appendChild(this.searchInput);
    this.dropdown.appendChild(this.list);

    this.wrapper.appendChild(this.trigger);
    this.wrapper.appendChild(this.dropdown);

    this.selectElement.insertAdjacentElement("afterend", this.wrapper);

    this.renderOptions();
  }

  destroy() {
    if (this.wrapper) {
      this.wrapper.remove();
      this.wrapper = null;
    }

    if (this.selectElement) {
      this.selectElement.style.display = "";
    }
  }

  bindEvents() {
    this.onTriggerClick = (event) => {
      if (event.target === this.clearBtn) return;
      this.toggle();
    };

    this.onClearClick = (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.clearSelection();
    };

    this.onSearchInput = () => this.filter();

    this.onSearchKeydown = (event) => this.handleKeydown(event);

    this.onTriggerKeydown = (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        this.open();
      }

      if (event.key === "ArrowDown") {
        event.preventDefault();
        this.open();
      }

      if (event.key === "Escape") {
        this.close();
      }
    };

    this.onOutsideClick = (event) => {
      if (!this.wrapper) return;
      if (!this.wrapper.contains(event.target)) this.close();
    };

    this.onNativeChange = () => {
      this.syncFromSelect();
      this.renderOptions();
    };

    this.trigger.addEventListener("click", this.onTriggerClick);
    this.trigger.addEventListener("keydown", this.onTriggerKeydown);
    this.clearBtn.addEventListener("click", this.onClearClick);
    this.searchInput.addEventListener("input", this.onSearchInput);
    this.searchInput.addEventListener("keydown", this.onSearchKeydown);
    this.selectElement.addEventListener("change", this.onNativeChange);
    document.addEventListener("click", this.onOutsideClick);
  }

  unbindEvents() {
    if (this.trigger && this.onTriggerClick) {
      this.trigger.removeEventListener("click", this.onTriggerClick);
    }

    if (this.trigger && this.onTriggerKeydown) {
      this.trigger.removeEventListener("keydown", this.onTriggerKeydown);
    }

    if (this.clearBtn && this.onClearClick) {
      this.clearBtn.removeEventListener("click", this.onClearClick);
    }

    if (this.searchInput && this.onSearchInput) {
      this.searchInput.removeEventListener("input", this.onSearchInput);
    }

    if (this.searchInput && this.onSearchKeydown) {
      this.searchInput.removeEventListener("keydown", this.onSearchKeydown);
    }

    if (this.selectElement && this.onNativeChange) {
      this.selectElement.removeEventListener("change", this.onNativeChange);
    }

    if (this.onOutsideClick) {
      document.removeEventListener("click", this.onOutsideClick);
    }
  }

  renderOptions() {
    if (!this.list) return;

    this.list.innerHTML = "";

    const options = Array.from(this.selectElement.options);

    options.forEach((option) => {
      if (!option.value && option.text.trim() === "") return;

      const item = document.createElement("li");
      item.className = "ss-option px-3 py-2 small";
      item.dataset.value = option.value;
      item.dataset.label = option.text;
      item.setAttribute("role", "option");
      item.textContent = option.text;

      if (!option.value) {
        item.classList.add("text-muted", "fst-italic");
      }

      if (option.selected) {
        item.classList.add("ss-selected", "fw-semibold", "text-primary");
      }

      item.addEventListener("click", () => this.select(option.value));
      item.addEventListener("mouseenter", () => this.setActive(item));

      this.list.appendChild(item);
    });
  }

  syncFromSelect() {
    const selectedOption =
      this.selectElement.options[this.selectElement.selectedIndex];

    if (selectedOption && selectedOption.value) {
      this.triggerText.textContent = selectedOption.text;
      this.triggerText.classList.remove("text-muted");
      this.clearBtn.style.display = "";
    } else {
      this.triggerText.textContent = this.placeholderValue;
      this.triggerText.classList.add("text-muted");
      this.clearBtn.style.display = "none";
    }
  }

  select(value) {
    this.selectElement.value = value;
    this.selectElement.dispatchEvent(new Event("change", { bubbles: true }));
    this.close();
  }

  clearSelection() {
    this.select("");
  }

  filter() {
    const query = this.normalize(this.searchInput.value);
    const options = Array.from(this.list.querySelectorAll(".ss-option"));
    let visibleCount = 0;

    options.forEach((option) => {
      const label = this.normalize(option.dataset.label || "");
      const visible = query === "" || label.includes(query);
      option.style.display = visible ? "" : "none";
      if (visible) visibleCount += 1;
    });

    this.renderNoResults(visibleCount === 0);
  }

  renderNoResults(show) {
    if (!this.noResultsElement) {
      this.noResultsElement = document.createElement("li");
      this.noResultsElement.className =
        "ss-no-results px-3 py-2 small text-muted fst-italic";
      this.noResultsElement.textContent = this.noResultsValue;
      this.list.appendChild(this.noResultsElement);
    }

    this.noResultsElement.style.display = show ? "" : "none";
  }

  handleKeydown(event) {
    const visibleOptions = Array.from(
      this.list.querySelectorAll(".ss-option"),
    ).filter((element) => element.style.display !== "none");

    if (visibleOptions.length === 0) return;

    const active = this.list.querySelector(".ss-active");
    let index = visibleOptions.indexOf(active);

    if (event.key === "ArrowDown") {
      event.preventDefault();
      index = Math.min(index + 1, visibleOptions.length - 1);
      this.setActive(visibleOptions[index]);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      index = Math.max(index - 1, 0);
      this.setActive(visibleOptions[index]);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const target = active || visibleOptions[0];
      if (target) this.select(target.dataset.value);
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.close();
      this.trigger.focus();
    }
  }

  setActive(element) {
    this.list.querySelectorAll(".ss-active").forEach((item) => {
      item.classList.remove("ss-active", "bg-primary-subtle");
    });

    if (!element) return;

    element.classList.add("ss-active", "bg-primary-subtle");
    element.scrollIntoView({ block: "nearest" });
  }

  open() {
    if (this.selectElement.disabled) return;

    this.dropdown.style.display = "block";
    this.trigger.setAttribute("aria-expanded", "true");
    this.searchInput.value = "";
    this.filter();

    const firstVisible = Array.from(
      this.list.querySelectorAll(".ss-option"),
    ).find((element) => element.style.display !== "none");

    this.setActive(firstVisible || null);
    this.searchInput.focus();
  }

  close() {
    if (!this.dropdown) return;
    this.dropdown.style.display = "none";
    this.trigger.setAttribute("aria-expanded", "false");
  }

  toggle() {
    if (this.dropdown.style.display === "none") {
      this.open();
    } else {
      this.close();
    }
  }

  disable() {
    this.selectElement.disabled = true;
    this.trigger.disabled = true;
    this.trigger.classList.add("disabled");
    this.close();
  }

  enable() {
    this.selectElement.disabled = false;
    this.trigger.disabled = false;
    this.trigger.classList.remove("disabled");
  }

  normalize(value) {
    return (value || "")
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim();
  }
}
