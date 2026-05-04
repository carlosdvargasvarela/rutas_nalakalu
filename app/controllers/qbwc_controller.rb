class QbwcController < ActionController::Base
  include QBWC::Controller

  skip_before_action :authenticate_user!, raise: false
  skip_after_action :verify_authorized, raise: false

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
