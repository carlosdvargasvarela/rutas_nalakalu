# app/controllers/pwa_controller.rb
class PwaController < ApplicationController
  # Saltamos la autenticación y la verificación de CSRF para los recursos de la PWA
  skip_before_action :authenticate_user!, only: [:manifest, :service_worker, :offline]
  skip_before_action :verify_authenticity_token, only: [:service_worker, :manifest]

  def manifest
    render formats: [:json]
  end

  def service_worker
    # Forzamos el content_type correcto para que el navegador lo acepte como SW
    render formats: [:js], content_type: "application/javascript"
  end

  def offline
    render "pwa/offline", layout: "driver"
  end
end
