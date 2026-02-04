// app/javascript/controllers/driver_assignment_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    id: Number,
    url: String,
  };

  static targets = ["statusBadge", "actionsContainer", "notesTextarea"];

  connect() {
    // console.log(`🚚 Assignment ${this.idValue} conectado`)
  }

  // Marcar como ENTREGADO
  async complete(event) {
    event.preventDefault();
    if (!confirm("¿Confirmar que la entrega fue exitosa?")) return;

    this.setLoading(true);

    try {
      const response = await fetch(`${this.urlValue}/complete`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
      });

      if (response.ok) {
        const data = await response.json();
        this.updateUI("delivered", "Entregado", "success");
        console.log("✅ Entrega completada");
      } else {
        throw new Error("Error en el servidor");
      }
    } catch (error) {
      alert("Error al marcar como entregado. Reintenta.");
      console.error(error);
    } finally {
      this.setLoading(false);
    }
  }

  // Marcar como FALLIDO
  async fail(event) {
    event.preventDefault();
    const reason = prompt("¿Por qué falló la entrega? (Opcional)");
    if (reason === null) return; // Usuario canceló el prompt

    this.setLoading(true);

    try {
      const response = await fetch(`${this.urlValue}/fail`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({ reason: reason }),
      });

      if (response.ok) {
        this.updateUI("failed", "Fallido", "danger");
        console.log("❌ Entrega marcada como fallida");
      }
    } catch (error) {
      alert("Error al marcar como fallida.");
    } finally {
      this.setLoading(false);
    }
  }

  // Guardar NOTA
  async saveNote(event) {
    event.preventDefault();
    const note = this.notesTextareaTarget.value;
    if (!note) return;

    const btn = event.currentTarget;
    const originalText = btn.innerHTML;
    btn.innerHTML = "Guardando...";
    btn.disabled = true;

    try {
      const response = await fetch(`${this.urlValue}/add_note`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({ note: note }),
      });

      if (response.ok) {
        btn.innerHTML = "✅ Guardado";
        setTimeout(() => {
          btn.innerHTML = originalText;
          btn.disabled = false;
        }, 2000);
      }
    } catch (error) {
      alert("Error al guardar nota");
      btn.innerHTML = originalText;
      btn.disabled = false;
    }
  }

  // Helpers de UI
  updateUI(status, label, badgeClass) {
    // Actualizar badge de estado
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = label;
      this.statusBadgeTarget.className = `badge bg-${badgeClass}`;
    }

    // Ocultar botones de acción si ya terminó
    if (this.hasActionsContainerTarget) {
      this.actionsContainerTarget.classList.add("d-none");
    }

    // Opcional: Recargar la página o usar Turbo para actualizar progreso general
    // window.location.reload()
  }

  setLoading(isLoading) {
    this.element.style.opacity = isLoading ? "0.5" : "1";
    this.element.style.pointerEvents = isLoading ? "none" : "auto";
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }
}
