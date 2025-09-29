import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["step", "nav", "icon", "nextButton", "submitButton",
        "summaryClient", "summaryOrder", "summaryAddress",
        "summaryDate", "summaryItems", "summaryContact", "summaryNotes",
        "summaryMapContainer", "summaryMap"]

    connect() {
        this.currentStep = 0
        this.showStep(0)
        this.bindFieldListeners()
    }

    showStep(index) {
        this.stepTargets.forEach((s, i) => {
            s.classList.toggle("d-none", i !== index)
        })
        this.currentStep = index

        const links = this.navTarget.querySelectorAll(".nav-link")
        links.forEach((link, i) => {
            // Remover active de todos
            link.classList.remove("active")
            // Agregar active solo al actual
            if (i === index) {
                link.classList.add("active")
            }
        })

        const total = this.stepTargets.length
        this.nextButtonTarget.classList.toggle("d-none", index === total - 1)
        this.submitButtonTarget.classList.toggle("d-none", index !== total - 1)

        if (index === total - 1) this.fillSummary()
        this.updateIcons()
    }

    next() { this.goTo(this.currentStep + 1) }
    prev() { this.goTo(this.currentStep - 1) }

    goToStep(event) {
        event.preventDefault()
        const index = parseInt(event.currentTarget.dataset.index, 10)
        this.goTo(index)
    }

    goTo(index) {
        if (index >= 0 && index < this.stepTargets.length) {
            this.showStep(index)
        }
    }

    // === 🚦 SEMÁFORO: Cambiar color de tabs según completitud ===
    updateIcons() {
        const links = this.navTarget.querySelectorAll(".nav-link")

        this.iconTargets.forEach(icon => {
            const step = parseInt(icon.dataset.step, 10)
            const completed = this.isStepComplete(step)
            const link = links[step]

            if (!link) return // Protección

            // 🔄 Resetear todas las clases de estado
            link.classList.remove("bg-success", "bg-danger", "text-white", "text-success", "text-danger")

            // 🚦 Aplicar estilo según completitud
            if (completed) {
                // ✅ Completado: fondo verde con texto blanco
                link.classList.add("bg-success", "text-white")
                icon.className = "bi bi-check-circle me-1"
            } else {
                // ❌ Incompleto: fondo rojo con texto blanco
                link.classList.add("bg-danger", "text-white")
                icon.className = "bi bi-exclamation-circle me-1"
            }

            // 🎯 Si es el paso activo, agregar un borde para destacar
            if (step === this.currentStep) {
                link.classList.add("border", "border-warning", "border-2")
            } else {
                link.classList.remove("border", "border-warning", "border-2")
            }
        })
    }

    isStepComplete(step) {
        switch (step) {
            case 0: return !!this.element.querySelector("[data-delivery-form-target='clientSelect']")?.value
            case 1: return !!this.element.querySelector("[data-delivery-form-target='orderSelect']")?.value
            case 2: return !!this.element.querySelector("[data-delivery-form-target='addressSelect']")?.value
            case 3: return !!this.element.querySelector("#delivery_delivery_date")?.value
            case 4:
                const visibleRows = this.element.querySelectorAll("#delivery-items-container tr:not(.delivery-item-template):not(.no-items-row)")
                return Array.from(visibleRows).some(row => row.style.display !== "none")
            case 5: return true // Confirmación siempre está "completa"
            default: return false
        }
    }

    // === Listeners para actualización en tiempo real ===
    bindFieldListeners() {
        const clientSelect = this.element.querySelector("[data-delivery-form-target='clientSelect']")
        if (clientSelect) {
            clientSelect.addEventListener('change', () => this.updateIcons())
        }

        const orderSelect = this.element.querySelector("[data-delivery-form-target='orderSelect']")
        if (orderSelect) {
            orderSelect.addEventListener('change', () => this.updateIcons())
        }

        const addressSelect = this.element.querySelector("[data-delivery-form-target='addressSelect']")
        if (addressSelect) {
            addressSelect.addEventListener('change', () => this.updateIcons())
        }

        const dateField = this.element.querySelector("#delivery_delivery_date")
        if (dateField) {
            dateField.addEventListener('change', () => this.updateIcons())
        }

        const itemsContainer = this.element.querySelector("#delivery-items-container")
        if (itemsContainer) {
            const observer = new MutationObserver(() => this.updateIcons())
            observer.observe(itemsContainer, { childList: true, subtree: true })
        }
    }

    // === Resumen Confirmación ===
    fillSummary() {
        // Cliente
        this.summaryClientTarget.innerText =
            this.element.querySelector("[data-delivery-form-target='clientSelect']")?.selectedOptions[0]?.text || "No definido"

        // Pedido
        this.summaryOrderTarget.innerText =
            this.element.querySelector("[data-delivery-form-target='orderSelect']")?.selectedOptions[0]?.text || "No definido"

        // Dirección
        const addressSelect = this.element.querySelector("[data-delivery-form-target='addressSelect']")
        const addressText = addressSelect?.selectedOptions[0]?.text || "No definida"
        this.summaryAddressTarget.innerText = addressText

        // 🗺️ MAPA - Mostrar si hay dirección válida
        this.showMapForAddress(addressText)

        // Fecha
        const dateValue = this.element.querySelector("#delivery_delivery_date")?.value
        this.summaryDateTarget.innerText = dateValue ? this.formatDate(dateValue) : "No definida"

        // Contacto
        const contactName = this.element.querySelector("#delivery_contact_name")?.value || ""
        const contactPhone = this.element.querySelector("#delivery_contact_phone")?.value || ""
        let contactText = "No definido"

        if (contactName && contactPhone) {
            contactText = `${contactName} (${contactPhone})`
        } else if (contactName) {
            contactText = contactName
        } else if (contactPhone) {
            contactText = contactPhone
        }

        this.summaryContactTarget.innerText = contactText

        // Notas
        const notes = this.element.querySelector("#delivery_delivery_notes")?.value
        this.summaryNotesTarget.innerText = notes || "Sin notas"

        // Productos
        const items = Array.from(this.element.querySelectorAll("#delivery-items-container tr"))
            .filter(tr => {
                return tr.style.display !== "none" &&
                    !tr.classList.contains("delivery-item-template") &&
                    !tr.classList.contains("no-items-row")
            })
            .map(tr => {
                const productInput = tr.querySelector("input[name*='[order_item_attributes][product]']")
                const quantityInput = tr.querySelector("input[name*='[quantity_delivered]']")
                const product = productInput?.value || "Producto sin nombre"
                const quantity = quantityInput?.value || "1"
                return `${product} (${quantity})`
            })

        if (items.length > 0) {
            this.summaryItemsTarget.innerHTML = items.map(item =>
                `<span class="badge bg-primary me-1 mb-1">${item}</span>`
            ).join("")
        } else {
            this.summaryItemsTarget.innerText = "Sin productos"
        }
    }

    // 🗺️ Método para mostrar/ocultar mapa
    showMapForAddress(addressText) {
        if (!this.hasSummaryMapContainerTarget || !this.hasSummaryMapTarget) return

        if (addressText && addressText !== "No definida" && window.GOOGLE_MAPS_API_KEY) {
            // Mostrar contenedor del mapa
            this.summaryMapContainerTarget.style.display = "block"

            // Cargar iframe de Google Maps
            const encodedAddress = encodeURIComponent(addressText)
            this.summaryMapTarget.innerHTML = `
                <iframe
                    width="100%"
                    height="300"
                    frameborder="0"
                    style="border:0"
                    referrerpolicy="no-referrer-when-downgrade"
                    src="https://www.google.com/maps/embed/v1/place?key=${window.GOOGLE_MAPS_API_KEY}&q=${encodedAddress}"
                    allowfullscreen>
                </iframe>
            `
        } else {
            // Ocultar mapa si no hay dirección
            this.summaryMapContainerTarget.style.display = "none"
            this.summaryMapTarget.innerHTML = ""
        }
    }

    // === Utilidades ===
    formatDate(dateString) {
        const date = new Date(dateString)
        return date.toLocaleDateString('es-CR', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        })
    }

    refreshIcons() {
        this.updateIcons()
    }
}