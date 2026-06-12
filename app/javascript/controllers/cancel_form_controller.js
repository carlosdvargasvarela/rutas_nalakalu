import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["simpleSection", "showroomSection"]

  connect() {
    this._updateView()
  }

  toggleMode() {
    this._updateView()
  }

  _updateView() {
    const mode = this.element.querySelector('input[name="cancel_mode"]:checked')?.value || "simple"
    this.simpleSectionTarget.classList.toggle("d-none", mode !== "simple")
    this.showroomSectionTarget.classList.toggle("d-none", mode !== "showroom")
  }
}
