// app/javascript/controllers/reschedule_form_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["newSection", "existingSection"];

  toggleMode(event) {
    const isNew = event.target.value === "true";
    this.newSectionTarget.classList.toggle("d-none", !isNew);
    this.existingSectionTarget?.classList.toggle("d-none", isNew);
  }
}
