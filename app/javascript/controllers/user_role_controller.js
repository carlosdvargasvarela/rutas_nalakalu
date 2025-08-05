import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["roleSelect", "sellerCodeField"]

    connect() {
        this.toggleSellerCode()
    }

    toggleSellerCode() {
        const selectedRole = this.roleSelectTarget.value

        if (selectedRole === "seller") {
            this.sellerCodeFieldTarget.style.display = "block"
            // Hacer el campo requerido cuando es visible
            const input = this.sellerCodeFieldTarget.querySelector("input")
            if (input) input.required = true
        } else {
            this.sellerCodeFieldTarget.style.display = "none"
            // Quitar el requerimiento cuando no es visible
            const input = this.sellerCodeFieldTarget.querySelector("input")
            if (input) {
                input.required = false
                input.value = "" // Limpiar el valor
            }
        }
    }
}