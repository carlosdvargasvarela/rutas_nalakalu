// app/javascript/controllers/client_note_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["display", "editForm"];
  static values = { noteId: Number, clientId: Number };

  showEdit() {
    this.displayTarget.classList.add("d-none");
    this.editFormTarget.classList.remove("d-none");
    this.editFormTarget.querySelector("textarea")?.focus();
  }

  cancelEdit() {
    this.editFormTarget.classList.add("d-none");
    this.displayTarget.classList.remove("d-none");
  }
}
