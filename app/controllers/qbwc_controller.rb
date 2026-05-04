class QbwcController < ActionController::Base
  include QBWC::Controller

  protected

  def server_version_response
    ""
  end

  def check_client_version
    ""
  end

  def app_name
    "Rutas Nalakalu"
  end
end
