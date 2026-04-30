import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  // Aquí podrías agregar un pooling si quisieras chequear notificaciones nuevas cada minuto
  // O simplemente usarlo para animar cuando se marca una como leída

  connect() {
    console.log("Notifications controller connected");
  }
}
