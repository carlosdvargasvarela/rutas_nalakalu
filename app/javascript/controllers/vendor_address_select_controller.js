import { Controller } from "@hotwired/stimulus";

// Fills the hidden delivery_address fields from the data-* attributes of the
// chosen <option>, mirroring what address-autocomplete does after a map pick.
export default class extends Controller {
  static targets = ["select", "address", "description", "latitude", "longitude", "plusCode", "editVendorLink"];
  static values = {urlTemplate: String};

  fill() {
    const option = this.selectTarget.selectedOptions[0];
    if (!option || !option.dataset.address) {
      this.editVendorLinkTarget.classList.add("d-none");
      return;
    }

    this.addressTarget.value = option.dataset.address || "";
    this.descriptionTarget.value = option.dataset.description || "";
    this.latitudeTarget.value = option.dataset.latitude || "";
    this.longitudeTarget.value = option.dataset.longitude || "";
    this.plusCodeTarget.value = option.dataset.plusCode || "";

    if (option.dataset.vendorId) {
      this.editVendorLinkTarget.href = this.urlTemplateValue.replace("__ID__", option.dataset.vendorId);
      this.editVendorLinkTarget.classList.remove("d-none");
    } else {
      this.editVendorLinkTarget.classList.add("d-none");
    }
  }
}
