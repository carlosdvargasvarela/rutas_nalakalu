// app/javascript/controllers/index.js
import { Application } from "@hotwired/stimulus"
import BootstrapController from "./bootstrap_controller"

window.Stimulus = Application.start()
Stimulus.register("bootstrap", BootstrapController)