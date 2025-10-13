// app/javascript/controllers/nested_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["template", "item"]

    add(e) {
        e.preventDefault()
        const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", Date.now().toString())
        this.element.querySelector("#crew-members-list").insertAdjacentHTML("beforeend", html)
    }

    remove(e) {
        e.preventDefault()
        const item = e.currentTarget.closest("[data-nested-form-target='item']")
        // Si tiene checkbox _destroy, marcarlo, si no, simplemente remover del DOM
        const destroyInput = item.querySelector("input[name*='[_destroy]']")
        if (destroyInput) {
            destroyInput.value = "1"
            item.style.display = "none"
        } else {
            item.remove()
        }
    }
}