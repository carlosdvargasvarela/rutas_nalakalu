// app/javascript/controllers/dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
// import { Chart, registerables } from 'chart.js'

// Chart.register(...registerables)

export default class extends Controller {
//     static targets = ["header", "metrics", "tasks", "notifications", "performance"]
//     static values = {
//         userRole: String,
//         metricsData: Object,
//         chartsData: Object
//     }

//     connect() {
//         this.initializeAnimations()
//         this.initializeCharts()
//         this.setupRealTimeUpdates()
//         this.setupKeyboardShortcuts()
//     }

//     disconnect() {
//         this.cleanup()
//     }

//     initializeAnimations() {
//         Configurar observer para animaciones de entrada
//         const observerOptions = {
//             threshold: 0.1,
//             rootMargin: '0px 0px -50px 0px'
//         }

//         this.observer = new IntersectionObserver((entries) => {
//             entries.forEach(entry => {
//                 if (entry.isIntersecting) {
//                     entry.target.classList.add('animate-in')
//                 }
//             })
//         }, observerOptions)

//         Observar elementos con animación
//         this.element.querySelectorAll('.fade-in').forEach(el => {
//             this.observer.observe(el)
//         })
//     }

//     initializeCharts() {
//         if (!this.chartsDataValue) return

//         Configuración global de Chart.js
//         Chart.defaults.font.family = 'Inter, sans-serif'
//         Chart.defaults.color = '#64748b'
//         Chart.defaults.plugins.legend.labels.usePointStyle = true

//         this.initializeWeeklyChart()
//         this.initializeDailyChart()
//         this.initializeStatusChart()
//     }

//     initializeWeeklyChart() {
//         const canvas = this.element.querySelector('#weeklyProgressChart')
//         if (!canvas) return

//         const ctx = canvas.getContext('2d')
//         this.weeklyChart = new Chart(ctx, {
//             type: 'doughnut',
//             data: {
//                 labels: ['Completadas', 'Pendientes', 'Programadas'],
//                 datasets: [{
//                     data: [
//                         this.chartsDataValue.weekly_progress?.completed || 0,
//                         this.chartsDataValue.weekly_progress?.pending || 0,
//                         this.chartsDataValue.weekly_progress?.scheduled || 0
//                     ],
//                     backgroundColor: ['#059669', '#dc2626', '#2563eb'],
//                     borderWidth: 0,
//                     cutout: '60%'
//                 }]
//             },
//             options: {
//                 responsive: true,
//                 maintainAspectRatio: false,
//                 plugins: {
//                     legend: {
//                         position: 'bottom',
//                         labels: {
//                             padding: 20,
//                             font: { size: 12 }
//                         }
//                     }
//                 },
//                 animation: {
//                     animateRotate: true,
//                     duration: 1000
//                 }
//             }
//         })
//     }

//     initializeDailyChart() {
//         const canvas = this.element.querySelector('#dailyDeliveriesChart')
//         if (!canvas) return

//         const ctx = canvas.getContext('2d')
//         const dailyData = this.chartsDataValue.daily_deliveries || {}

//         this.dailyChart = new Chart(ctx, {
//             type: 'line',
//             data: {
//                 labels: Object.keys(dailyData),
//                 datasets: [{
//                     label: 'Entregas completadas',
//                     data: Object.values(dailyData),
//                     borderColor: '#2563eb',
//                     backgroundColor: 'rgba(37, 99, 235, 0.1)',
//                     fill: true,
//                     tension: 0.4,
//                     pointBackgroundColor: '#2563eb',
//                     pointBorderColor: '#ffffff',
//                     pointBorderWidth: 2,
//                     pointRadius: 4
//                 }]
//             },
//             options: {
//                 responsive: true,
//                 maintainAspectRatio: false,
//                 plugins: {
//                     legend: { display: false }
//                 },
//                 scales: {
//                     y: {
//                         beginAtZero: true,
//                         grid: { color: 'rgba(0,0,0,0.05)' },
//                         ticks: { font: { size: 11 } }
//                     },
//                     x: {
//                         grid: { display: false },
//                         ticks: { font: { size: 11 } }
//                     }
//                 },
//                 animation: {
//                     duration: 1500,
//                     easing: 'easeInOutQuart'
//                 }
//             }
//         })
//     }

//     initializeStatusChart() {
//         const canvas = this.element.querySelector('#ordersStatusChart')
//         if (!canvas) return

//         const ctx = canvas.getContext('2d')
//         const statusData = this.chartsDataValue.orders_by_status || {}

//         this.statusChart = new Chart(ctx, {
//             type: 'pie',
//             data: {
//                 labels: Object.keys(statusData),
//                 datasets: [{
//                     data: Object.values(statusData),
//                     backgroundColor: ['#d97706', '#2563eb', '#059669', '#64748b'],
//                     borderWidth: 0
//                 }]
//             },
//             options: {
//                 responsive: true,
//                 maintainAspectRatio: false,
//                 plugins: {
//                     legend: {
//                         position: 'bottom',
//                         labels: {
//                             padding: 15,
//                             font: { size: 11 }
//                         }
//                     }
//                 },
//                 animation: {
//                     animateRotate: true,
//                     duration: 1200
//                 }
//             }
//         })
//     }

//     setupRealTimeUpdates() {
//         Actualizar métricas cada 30 segundos
//         this.updateInterval = setInterval(() => {
//             this.updateMetrics()
//         }, 30000)

//         Actualizar notificaciones cada 60 segundos
//         this.notificationInterval = setInterval(() => {
//             this.updateNotifications()
//         }, 60000)
//     }

//     setupKeyboardShortcuts() {
//         document.addEventListener('keydown', this.handleKeyboardShortcut.bind(this))
//     }

//     handleKeyboardShortcut(event) {
//         Solo procesar si no estamos en un input
//         if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') return

//         switch (event.key) {
//             case 'n':
//                 if (event.ctrlKey || event.metaKey) {
//                     event.preventDefault()
//                     this.navigateToNewDelivery()
//                 }
//                 break
//             case 'r':
//                 if (event.ctrlKey || event.metaKey) {
//                     event.preventDefault()
//                     this.refreshDashboard()
//                 }
//                 break
//             case '?':
//                 event.preventDefault()
//                 this.showKeyboardShortcuts()
//                 break
//         }
//     }

//     Métodos de actualización
//     async updateMetrics() {
//         try {
//             const response = await fetch('/dashboard.json', {
//                 headers: {
//                     'Accept': 'application/json',
//                     'X-Requested-With': 'XMLHttpRequest'
//                 }
//             })

//             if (response.ok) {
//                 const data = await response.json()
//                 this.updateMetricsDisplay(data.metrics)
//             }
//         } catch (error) {
//             console.error('Error updating metrics:', error)
//         }
//     }

//     updateMetricsDisplay(metrics) {
//         Object.entries(metrics).forEach(([key, metric]) => {
//             const card = this.element.querySelector(`[data-metric="${key}"]`)
//             if (card) {
//                 const valueElement = card.querySelector('[data-metric-card-target="value"]')
//                 if (valueElement) {
//                     this.animateValue(valueElement, parseInt(valueElement.textContent), metric.current)
//                 }
//             }
//         })
//     }

//     animateValue(element, start, end) {
//         const duration = 1000
//         const startTime = performance.now()

//         const animate = (currentTime) => {
//             const elapsed = currentTime - startTime
//             const progress = Math.min(elapsed / duration, 1)

//             const current = Math.round(start + (end - start) * this.easeOutQuart(progress))
//             element.textContent = current

//             if (progress < 1) {
//                 requestAnimationFrame(animate)
//             }
//         }

//         requestAnimationFrame(animate)
//     }

//     easeOutQuart(t) {
//         return 1 - Math.pow(1 - t, 4)
//     }

//     async updateNotifications() {
//         try {
//             const response = await fetch('/notifications.json?limit=5', {
//                 headers: {
//                     'Accept': 'application/json',
//                     'X-Requested-With': 'XMLHttpRequest'
//                 }
//             })

//             if (response.ok) {
//                 const data = await response.json()
//                 this.updateNotificationsDisplay(data.notifications)
//             }
//         } catch (error) {
//             console.error('Error updating notifications:', error)
//         }
//     }

//     updateNotificationsDisplay(notifications) {
//         const container = this.notificationsTarget.querySelector('.notifications-list')
//         if (container && notifications.length > 0) {
//             Actualizar solo si hay nuevas notificaciones
//             const currentCount = container.children.length
//             if (notifications.length > currentCount) {
//                 this.showNotificationToast('Tienes nuevas notificaciones')
//             }
//         }
//     }

//     Métodos de navegación
//     navigateToNewDelivery() {
//         const newDeliveryBtn = this.element.querySelector('a[href*="new_delivery"]')
//         if (newDeliveryBtn) {
//             newDeliveryBtn.click()
//         }
//     }

//     refreshDashboard() {
//         window.location.reload()
//     }

//     showKeyboardShortcuts() {
//         const shortcuts = [
//             { key: 'Ctrl/Cmd + N', action: 'Nueva entrega' },
//             { key: 'Ctrl/Cmd + R', action: 'Actualizar dashboard' },
//             { key: '?', action: 'Mostrar atajos' }
//         ]

//         Mostrar modal con atajos (implementar según necesidad)
//         console.table(shortcuts)
//     }

//     Métodos de utilidad
//     showNotificationToast(message) {
//         Crear toast notification
//         const toast = document.createElement('div')
//         toast.className = 'toast-notification'
//         toast.textContent = message
//         toast.style.cssText = `
//       position: fixed;
//       top: 20px;
//       right: 20px;
//       background: var(--nalakalu-primary);
//       color: white;
//       padding: 1rem 1.5rem;
//       border-radius: 8px;
//       box-shadow: 0 4px 12px rgba(0,0,0,0.15);
//       z-index: 1050;
//       transform: translateX(100%);
//       transition: transform 0.3s ease;
//     `

//         document.body.appendChild(toast)

//         Animar entrada
//         setTimeout(() => {
//             toast.style.transform = 'translateX(0)'
//         }, 100)

//         Remover después de 3 segundos
//         setTimeout(() => {
//             toast.style.transform = 'translateX(100%)'
//             setTimeout(() => {
//                 document.body.removeChild(toast)
//             }, 300)
//         }, 3000)
//     }

//     cleanup() {
//         Limpiar intervalos
//         if (this.updateInterval) clearInterval(this.updateInterval)
//         if (this.notificationInterval) clearInterval(this.notificationInterval)

//         Limpiar observer
//         if (this.observer) this.observer.disconnect()

//         Destruir gráficos
//         if (this.weeklyChart) this.weeklyChart.destroy()
//         if (this.dailyChart) this.dailyChart.destroy()
//         if (this.statusChart) this.statusChart.destroy()

//         Remover event listeners
//         document.removeEventListener('keydown', this.handleKeyboardShortcut.bind(this))
//     }
// }

// Controlador para cards de métricas individuales
// export class MetricCardController extends Controller {
//     static targets = ["value"]
//     static values = { value: Number }

//     connect() {
//         this.animateOnLoad()
//     }

//     animateOnLoad() {
//         const finalValue = this.valueValue
//         this.animateValue(0, finalValue, 1500)
//     }

//     animateValue(start, end, duration) {
//         const startTime = performance.now()

//         const animate = (currentTime) => {
//             const elapsed = currentTime - startTime
//             const progress = Math.min(elapsed / duration, 1)

//             const current = Math.round(start + (end - start) * this.easeOutCubic(progress))
//             this.valueTarget.textContent = current

//             if (progress < 1) {
//                 requestAnimationFrame(animate)
//             }
//         }

//         requestAnimationFrame(animate)
//     }

//     easeOutCubic(t) {
//         return 1 - Math.pow(1 - t, 3)
//     }
// }

// Controlador para items de tareas
// export class TaskItemController extends Controller {
//     static values = { priority: String }

//     connect() {
//         this.setupHoverEffects()
//     }

//     setupHoverEffects() {
//         this.element.addEventListener('mouseenter', this.handleMouseEnter.bind(this))
//         this.element.addEventListener('mouseleave', this.handleMouseLeave.bind(this))
//     }

//     handleMouseEnter() {
//         if (this.priorityValue === 'high') {
//             this.element.style.transform = 'translateX(8px) scale(1.02)'
//         } else {
//             this.element.style.transform = 'translateX(4px)'
//         }
//     }

//     handleMouseLeave() {
//         this.element.style.transform = 'translateX(0) scale(1)'
//     }
// }

// Controlador para items de notificaciones
// export class NotificationItemController extends Controller {
//     static values = {
//         notificationId: Number,
//         read: Boolean
//     }

//     connect() {
//         this.setupClickHandler()
//     }

//     setupClickHandler() {
//         if (!this.readValue) {
//             this.element.addEventListener('click', this.markAsRead.bind(this))
//         }
//     }

//     async markAsRead() {
//         if (this.readValue) return

//         try {
//             const response = await fetch(`/notifications/${this.notificationIdValue}/mark_as_read`, {
//                 method: 'PATCH',
//                 headers: {
//                     'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
//                     'Accept': 'application/json'
//                 }
//             })

//             if (response.ok) {
//                 this.element.classList.remove('bg-light')
//                 this.element.querySelector('.notification-dot')?.remove()
//                 this.element.querySelector('.badge')?.remove()
//                 this.readValue = true
//             }
//         } catch (error) {
//             console.error('Error marking notification as read:', error)
//         }
//     }
}