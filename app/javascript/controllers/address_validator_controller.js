import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["addressInput", "submitButton"];

  connect() {
    console.log("AddressValidatorController connected");
    this.originalSubmitText = this.hasSubmitButtonTarget
      ? this.submitButtonTarget.textContent
      : "";
  }

  validateAddress(event) {
    const addressValue = event.target.value.trim();

    // Patrones para detectar URLs
    const urlPatterns = [
      /https?:\/\//i, // http:// o https://
      /www\./i, // www.
      /waze\.com/i, // waze.com
      /maps\.google/i, // maps.google
      /goo\.gl/i, // goo.gl (Google Maps short)
      /maps\.app\.goo\.gl/i, // maps.app.goo.gl
      /uber\.com/i, // uber.com
      /bit\.ly/i, // bit.ly
      /tinyurl\.com/i, // tinyurl.com
      /[a-z0-9-]+\.(com|net|org|cr)/i, // dominios comunes
    ];

    const containsUrl = urlPatterns.some((pattern) =>
      pattern.test(addressValue)
    );

    if (containsUrl) {
      this.showUrlWarning(event.target);
      this.disableSubmit();
    } else {
      this.hideUrlWarning(event.target);
      this.enableSubmit();
    }
  }

  showUrlWarning(inputElement) {
    // Remover advertencia existente si hay
    this.hideUrlWarning(inputElement);

    // Crear advertencia
    const warning = document.createElement("div");
    warning.className = "alert alert-danger mt-2 address-url-warning";
    warning.innerHTML = `
      <div class="d-flex align-items-start">
        <i class="bi bi-exclamation-triangle-fill me-2 fs-5"></i>
        <div>
          <strong>⚠️ No se permiten enlaces en las direcciones</strong>
          <p class="mb-0 small">
            Por favor, ingrese la dirección de forma descriptiva en lugar de un enlace de Waze, Google Maps u otro servicio.
          </p>
          <p class="mb-0 small mt-1">
            <strong>Ejemplo correcto:</strong> "200 metros norte de la Iglesia, casa blanca con portón negro"
          </p>
        </div>
      </div>
    `;

    // Agregar clase de error al input
    inputElement.classList.add("is-invalid");

    // Insertar advertencia después del input o su contenedor
    const container =
      inputElement.closest(".form-group") || inputElement.parentElement;
    container.appendChild(warning);

    // Scroll suave hacia la advertencia
    warning.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  hideUrlWarning(inputElement) {
    // Remover clase de error
    inputElement.classList.remove("is-invalid");

    // Remover advertencias existentes
    const container =
      inputElement.closest(".form-group") || inputElement.parentElement;
    const warnings = container.querySelectorAll(".address-url-warning");
    warnings.forEach((warning) => warning.remove());
  }

  disableSubmit() {
    if (!this.hasSubmitButtonTarget) return;

    this.submitButtonTarget.disabled = true;
    this.submitButtonTarget.classList.add("btn-danger");
    this.submitButtonTarget.classList.remove(
      "btn-primary",
      "btn-success",
      "btn-warning"
    );
    this.submitButtonTarget.innerHTML = `
      <i class="bi bi-exclamation-triangle me-2"></i>
      Corrija los errores para continuar
    `;
  }

  enableSubmit() {
    if (!this.hasSubmitButtonTarget) return;

    // Verificar que no haya otros errores de URL en el formulario
    const allAddressInputs = this.element.querySelectorAll(
      "[data-address-validator-target='addressInput']"
    );
    const hasAnyUrlError = Array.from(allAddressInputs).some((input) =>
      input.classList.contains("is-invalid")
    );

    if (!hasAnyUrlError) {
      this.submitButtonTarget.disabled = false;
      this.submitButtonTarget.classList.remove("btn-danger");
      this.submitButtonTarget.classList.add("btn-primary");
      this.submitButtonTarget.textContent = this.originalSubmitText;
    }
  }

  // Validar antes de enviar el formulario
  validateBeforeSubmit(event) {
    const allAddressInputs = this.element.querySelectorAll(
      "[data-address-validator-target='addressInput']"
    );

    let hasUrlError = false;

    allAddressInputs.forEach((input) => {
      const addressValue = input.value.trim();

      const urlPatterns = [
        /https?:\/\//i,
        /www\./i,
        /waze\.com/i,
        /maps\.google/i,
        /goo\.gl/i,
        /maps\.app\.goo\.gl/i,
        /uber\.com/i,
        /bit\.ly/i,
        /tinyurl\.com/i,
        /[a-z0-9-]+\.(com|net|org|cr)/i,
      ];

      const containsUrl = urlPatterns.some((pattern) =>
        pattern.test(addressValue)
      );

      if (containsUrl) {
        hasUrlError = true;
        this.showUrlWarning(input);
      }
    });

    if (hasUrlError) {
      event.preventDefault();
      event.stopPropagation();

      // Mostrar alerta modal
      this.showModalAlert();

      return false;
    }

    return true;
  }

  showModalAlert() {
    // Crear modal de Bootstrap si no existe
    let modal = document.getElementById("urlErrorModal");

    if (!modal) {
      modal = document.createElement("div");
      modal.id = "urlErrorModal";
      modal.className = "modal fade";
      modal.innerHTML = `
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content border-danger">
            <div class="modal-header bg-danger text-white">
              <h5 class="modal-title">
                <i class="bi bi-exclamation-triangle-fill me-2"></i>
                No se puede guardar
              </h5>
              <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
              <p class="mb-2">
                <strong>Se detectaron enlaces en los campos de dirección.</strong>
              </p>
              <p class="mb-2">
                Por favor, ingrese las direcciones de forma descriptiva en lugar de enlaces de Waze, Google Maps u otros servicios.
              </p>
              <div class="alert alert-info mb-0">
                <strong>Ejemplo correcto:</strong><br>
                "200 metros norte de la Iglesia Católica, casa blanca con portón negro, frente al supermercado"
              </div>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-primary" data-bs-dismiss="modal">
                Entendido
              </button>
            </div>
          </div>
        </div>
      `;
      document.body.appendChild(modal);
    }

    const bsModal = new bootstrap.Modal(modal);
    bsModal.show();
  }
}
