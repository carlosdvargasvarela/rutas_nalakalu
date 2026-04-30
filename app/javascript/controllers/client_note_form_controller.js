// app/javascript/controllers/client_note_form_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["body"];

  clearOnSuccess(event) {
    // Solo limpiamos si el form submit fue exitoso (turbo:submit-end con status 2xx)
    const form = event.target;
    form.addEventListener(
      "turbo:submit-end",
      (e) => {
        if (e.detail.success) {
          if (this.hasBodyTarget) {
            this.bodyTarget.value = "";
          }
          // Reset checkboxes y selects
          form.querySelectorAll("select").forEach((s) => (s.selectedIndex = 0));
          form
            .querySelectorAll("input[type=checkbox]")
            .forEach((c) => (c.checked = false));
        }
      },
      { once: true },
    );
  }
}
