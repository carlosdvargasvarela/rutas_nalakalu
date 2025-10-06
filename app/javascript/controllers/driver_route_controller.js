import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { nextAssignmentId: Number }

    connect() {
        this.scrollToNext()
    }

    scrollToNext() {
        const id = this.nextAssignmentIdValue
        if (!id) return
        const el = document.getElementById(`assignment_${id}`)
        if (!el) return
        el.scrollIntoView({ behavior: "smooth", block: "start" })
        // Pequeño highlight
        el.classList.add("ring-highlight")
        setTimeout(() => el.classList.remove("ring-highlight"), 1500)
    }
}