class QbwcController < ApplicationController
  # Importante: No heredar de un controlador que tenga filtros de usuario si es posible
  include QBWC::Controller

  # Saltamos todas las protecciones de sesión de usuario
  skip_before_action :authenticate_user!, raise: false
  skip_after_action :verify_authorized, raise: false
  skip_after_action :verify_policy_scoped, raise: false

  # Desactivamos CSRF ya que SOAP no lo usa
  skip_before_action :verify_authenticity_token, raise: false

  # 1. El método que ya teníamos
  def authenticate(username, password)
    user = ENV.fetch("QB_USER", "admin").strip
    pass = ENV.fetch("QB_PASS", "Acesa2023").strip

    if username.to_s.strip == user && password.to_s.strip == pass
      # Retornamos un Ticket único y nil para indicar "Sin errores"
      [SecureRandom.uuid, nil]
    else
      Rails.logger.error "QB Auth Falló: Recibido #{username}"
      ["", "nvu"]
    end
  end

  # 2. Métodos obligatorios para que no de error 500
  def server_version(str_version)
    ""
  end

  def client_version(str_version)
    ""
  end

  def connection_error(ticket, hresult, message)
    Rails.logger.error "QB Error de conexión: #{message}"
    "done"
  end

  def close_connection(ticket)
    "OK"
  end
end
