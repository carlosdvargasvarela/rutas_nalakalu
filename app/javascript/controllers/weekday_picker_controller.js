import { Controller } from "@hotwired/stimulus"

// Conecta con data-controller="weekday-picker"
export default class extends Controller {
  static values = { weekday: Number }

  connect() {
    this.input = this.element
    this.input.addEventListener("change", this.validateDate.bind(this))
    this.input.addEventListener("input", this.validateDate.bind(this))
  }

  disconnect() {
    this.input.removeEventListener("change", this.validateDate.bind(this))
    this.input.removeEventListener("input", this.validateDate.bind(this))
  }

  // validateDate(event) {
  //   const selectedValue = this.input.value
  //   if (!selectedValue) return

  //   const selected = new Date(selectedValue + "T00:00:00")
  //   const requiredWeekday = this.weekdayValue
  //   const selectedWeekday = selected.getDay()

  //   if (selectedWeekday !== requiredWeekday) {
  //     this.showError()
  //     this.input.value = "" // resetea el campo
  //     this.input.focus()
  //   }
  // }

  // showError() {
  //   const dayName = this.dayName(this.weekdayValue)
  //   alert(`⚠️ Solo puedes seleccionar ${dayName} para reagendar`)
  // }

  // dayName(weekday) {
  //   const days = ["domingos","lunes","martes","miércoles","jueves","viernes","sábados"]
  //   return days[weekday]
  // }
}