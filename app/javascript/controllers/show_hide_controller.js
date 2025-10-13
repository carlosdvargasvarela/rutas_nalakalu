// app/javascript/controllers/show_hide_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { role: String }

  connect() {
    this.toggle()
    document.addEventListener("change", this.onChange)
  }

  disconnect() {
    document.removeEventListener("change", this.onChange)
  }

  onChange = (e) => {
    if (e.target.matches("#user_role")) this.toggle()
  }

  toggle() {
    const roleSelect = document.querySelector("#user_role")
    const isDriver = roleSelect && roleSelect.value === this.roleValue
    this.element.style.display = isDriver ? "" : "none"
  }
}