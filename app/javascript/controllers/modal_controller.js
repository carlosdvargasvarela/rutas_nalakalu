// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.modal = new window.bootstrap.Modal(this.element)

        const frame = this.element.querySelector('turbo-frame[id="note_modal"]')
        if (frame) {
            this.observer = new MutationObserver(() => {
                if (frame.innerHTML.trim() !== '') {
                    this.modal.show()

                    this.element.addEventListener(
                        "hidden.bs.modal",
                        () => { frame.innerHTML = '' },
                        { once: true }
                    )
                }
            })
            this.observer.observe(frame, { childList: true, subtree: true })
        }
    }

    disconnect() {
        if (this.observer) this.observer.disconnect()
        if (this.modal) this.modal.dispose()
    }
}