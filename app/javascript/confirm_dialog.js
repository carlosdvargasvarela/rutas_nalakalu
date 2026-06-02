// app/javascript/confirm_dialog.js
export function confirmDialog(message, { danger = false } = {}) {
  return new Promise((resolve) => {
    const existing = document.getElementById("confirm-dialog");
    if (existing) existing.remove();

    let resolved = false;

    const el = document.createElement("div");
    el.id = "confirm-dialog";
    el.className = "modal fade";
    el.setAttribute("tabindex", "-1");
    el.setAttribute("aria-hidden", "true");

    const icon = danger
      ? `<i class="bi bi-exclamation-triangle-fill text-danger" style="font-size:2rem;"></i>`
      : `<i class="bi bi-question-circle-fill text-primary" style="font-size:2rem;"></i>`;

    el.innerHTML = `
      <div class="modal-dialog modal-dialog-centered" style="max-width:380px;">
        <div class="modal-content border-0 shadow-lg rounded-4">
          <div class="modal-body px-4 pt-4 pb-3 text-center">
            <div class="mb-3">${icon}</div>
            <p class="mb-0 text-muted" style="font-size:0.95rem;">${message}</p>
          </div>
          <div class="modal-footer border-0 px-4 pb-4 pt-1 justify-content-center gap-2">
            <button type="button" class="btn btn-outline-secondary px-4" id="confirm-cancel-btn">
              Cancelar
            </button>
            <button type="button" class="btn ${danger ? "btn-danger" : "btn-primary"} px-4" id="confirm-ok-btn">
              Continuar
            </button>
          </div>
        </div>
      </div>
    `;

    document.body.appendChild(el);

    const bsModal = new bootstrap.Modal(el, { backdrop: "static", keyboard: false });

    el.querySelector("#confirm-ok-btn").addEventListener("click", () => {
      resolved = true;
      bsModal.hide();
      resolve(true);
    });

    el.querySelector("#confirm-cancel-btn").addEventListener("click", () => {
      bsModal.hide();
    });

    el.addEventListener("hidden.bs.modal", () => {
      el.remove();
      if (!resolved) resolve(false);
    }, { once: true });

    bsModal.show();
  });
}
