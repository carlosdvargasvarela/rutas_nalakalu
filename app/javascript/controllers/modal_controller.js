import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.modal = new window.bootstrap.Modal(this.element)
        console.log("Modal controller connected")

        // Observar cambios en el turbo-frame
        const frame = this.element.querySelector('turbo-frame[id="note_modal"]')
        if (frame) {
            this.observer = new MutationObserver(() => {
                if (frame.innerHTML.trim() !== '') {
                    this.showModal()
                }
            })
            this.observer.observe(frame, { childList: true, subtree: true })
        }
    }

    disconnect() {
        if (this.observer) {
            this.observer.disconnect()
        }
        if (this.modal) {
            this.modal.dispose()
        }
    }

    showModal() {
        this.modal.show()

        // Limpiar cuando se cierre
        this.element.addEventListener("hidden.bs.modal", () => {
            const frame = this.element.querySelector('turbo-frame[id="note_modal"]')
            if (frame) {
                frame.innerHTML = ''
            }
        }, { once: true })
    }
}