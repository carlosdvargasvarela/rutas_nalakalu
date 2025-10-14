import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        csrf: String
    }

    connect() {
        this.csrfToken = this.csrfValue || document.querySelector('meta[name="csrf-token"]')?.content

        // Escuchar cuando vuelve la conexión
        window.addEventListener('online', () => this.onOnline())
    }

    async handleAction(event) {
        // Si estamos online, dejar que Turbo maneje normalmente
        if (navigator.onLine) {
            return
        }

        // Si estamos offline, interceptar y guardar
        event.preventDefault()
        event.stopPropagation()

        const form = event.target.closest('form')
        if (!form) return

        const url = form.action
        const method = form.method.toUpperCase()
        const formData = new FormData(form)
        const body = new URLSearchParams(formData).toString()

        await this.queueAction({
            url: url,
            method: method,
            body: body,
            csrf: this.csrfToken
        })

        this.showOfflineNotice(form)
        this.markAsPending(form)
    }

    async queueAction(action) {
        const db = await this.openDB()
        const tx = db.transaction('pending-actions', 'readwrite')
        const store = tx.objectStore('pending-actions')

        await store.add({
            ...action,
            timestamp: Date.now()
        })

        console.log('Acción guardada para sincronizar:', action)
    }

    markAsPending(form) {
        const card = form.closest('.card')
        if (card) {
            card.classList.add('border-warning', 'border-2')

            // Añadir badge de pendiente
            const cardBody = card.querySelector('.card-body')
            if (cardBody && !cardBody.querySelector('.pending-sync-badge')) {
                const badge = document.createElement('span')
                badge.className = 'badge bg-warning text-dark pending-sync-badge'
                badge.innerHTML = '<i class="bi bi-clock-history me-1"></i>Pendiente de sincronizar'
                cardBody.insertBefore(badge, cardBody.firstChild)
            }

            // Deshabilitar botones
            const buttons = card.querySelectorAll('button, input[type="submit"]')
            buttons.forEach(btn => {
                btn.disabled = true
                btn.classList.add('disabled')
            })
        }
    }

    showOfflineNotice(form) {
        const flashContainer = document.getElementById('flash')
        if (flashContainer) {
            const alert = document.createElement('div')
            alert.className = 'alert alert-warning alert-dismissible fade show'
            alert.innerHTML = `
        <i class="bi bi-wifi-off me-2"></i>
        <strong>Sin conexión:</strong> La acción se sincronizará automáticamente cuando vuelvas a tener internet.
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
      `
            flashContainer.appendChild(alert)

            setTimeout(() => {
                alert.remove()
            }, 5000)
        }
    }

    async onOnline() {
        console.log('Conexión restaurada, intentando sincronizar...')

        if ('serviceWorker' in navigator && 'sync' in ServiceWorkerRegistration.prototype) {
            const registration = await navigator.serviceWorker.ready
            try {
                await registration.sync.register('sync-actions')
            } catch (error) {
                console.error('Error registrando sync:', error)
            }
        }
    }

    openDB() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open('nalakalu-db', 1)

            request.onerror = () => reject(request.error)

            request.onupgradeneeded = (event) => {
                const db = event.target.result
                if (!db.objectStoreNames.contains('pending-actions')) {
                    db.createObjectStore('pending-actions', { keyPath: 'id', autoIncrement: true })
                }
            }

            request.onsuccess = () => resolve(request.result)
        })
    }
}