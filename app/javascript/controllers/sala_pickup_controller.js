import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "select",
    "addressCard",
    "nameDisplay",
    "addressDisplay",
    "descriptionDisplay",
    "noAddress",
    "lat", "lng", "plusCode", "address", "description"
  ]
  static values = { showrooms: Array }

  connect() {
    this.updateAddress()
  }

  updateAddress() {
    const code = this.selectTarget.value
    const showroom = this.showroomsValue.find(s => s.code === code)

    if (!showroom?.has_address) {
      this.addressCardTarget.classList.add("d-none")
      this.noAddressTarget.classList.remove("d-none")
      this._clearHiddenFields()
      return
    }

    this.nameDisplayTarget.textContent        = showroom.name
    this.addressDisplayTarget.textContent     = showroom.address || ""
    this.descriptionDisplayTarget.textContent = showroom.description || ""
    this.descriptionDisplayTarget.classList.toggle("d-none", !showroom.description)

    this.latTarget.value         = showroom.latitude    || ""
    this.lngTarget.value         = showroom.longitude   || ""
    this.plusCodeTarget.value    = showroom.plus_code   || ""
    this.addressTarget.value     = showroom.address     || ""
    this.descriptionTarget.value = showroom.description || ""

    this.addressCardTarget.classList.remove("d-none")
    this.noAddressTarget.classList.add("d-none")
  }

  _clearHiddenFields() {
    this.latTarget.value         = ""
    this.lngTarget.value         = ""
    this.plusCodeTarget.value    = ""
    this.addressTarget.value     = ""
    this.descriptionTarget.value = ""
  }
}
