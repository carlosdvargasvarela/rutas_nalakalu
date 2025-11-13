import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["notice"];

  connect() {
    console.log("ServiceTypeController connected");
  }

  updateNotice(event) {
    const selectedType = event.target.value;

    if (!this.hasNoticeTarget) return;

    const messages = {
      pickup_with_return: `
        <i class="bi bi-arrow-return-right me-1 text-warning"></i>
        Se crearán dos casos: <strong>Recogida</strong> en la fecha indicada y <strong>Devolución</strong> automáticamente <strong>+15 días</strong> después, con los mismos productos.
      `,
      only_pickup: `
        <i class="bi bi-truck me-1 text-secondary"></i> 
        Solo se registrará la <strong>Recogida</strong>.
      `,
      return_delivery: `
        <i class="bi bi-arrow-counterclockwise me-1 text-secondary"></i> 
        Registrar una <strong>Devolución</strong>.
      `,
      onsite_repair: `
        <i class="bi bi-wrench me-1 text-secondary"></i> 
        Registrar una <strong>Reparación en sitio</strong>.
      `,
      "": `
        <i class="bi bi-info-circle me-1 text-muted"></i> 
        Selecciona el tipo de servicio para ver los detalles.
      `,
    };

    this.noticeTarget.innerHTML = messages[selectedType] || messages[""];
  }
}
