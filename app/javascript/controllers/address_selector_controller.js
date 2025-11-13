import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "select",
    "details",
    "detailAddress",
    "detailReference",
    "detailLat",
    "detailLng",
    "detailPlusCode",
    "map",
  ];

  connect() {
    console.log("AddressSelectorController connected");
  }

  async updateMap(event) {
    const addressId = event.target.value;

    if (!addressId) {
      this.hideDetails();
      return;
    }

    try {
      // Obtener datos de la dirección
      const response = await fetch(`/delivery_addresses/${addressId}.json`);
      const address = await response.json();

      // Actualizar detalles
      this.showDetails(address);

      // Actualizar mapa
      this.updateMapPosition(address.latitude, address.longitude);
    } catch (error) {
      console.error("Error loading address details:", error);
    }
  }

  showDetails(address) {
    if (!this.hasDetailsTarget) return;

    this.detailAddressTarget.textContent = address.address || "N/A";
    this.detailReferenceTarget.textContent =
      address.description || "Sin referencia";
    this.detailLatTarget.textContent = address.latitude || "N/A";
    this.detailLngTarget.textContent = address.longitude || "N/A";
    this.detailPlusCodeTarget.textContent = address.plus_code || "N/A";

    this.detailsTarget.classList.remove("d-none");
  }

  hideDetails() {
    if (this.hasDetailsTarget) {
      this.detailsTarget.classList.add("d-none");
    }
  }

  updateMapPosition(lat, lng) {
    if (!this.hasMapTarget) return;

    // Buscar el controller del mapa
    const mapController = this.application.getControllerForElementAndIdentifier(
      this.mapTarget,
      "address-map"
    );

    if (mapController && mapController.updateMap) {
      mapController.updateMap(lat, lng);
    }
  }
}
