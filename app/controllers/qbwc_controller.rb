class QbwcController < ActionController::Base
  include QBWC::Controller

  def authenticate
    Rails.logger.info "QBWC PARAMS: #{params.to_unsafe_h.inspect}"

    user = ENV["QB_USER"] || "admin"
    pass = ENV["QB_PASS"] || "123456"

    if params[:strUserName].to_s.strip == user && params[:strPassword].to_s.strip == pass
      ticket = SecureRandom.uuid
      render soap: {authRet: [ticket, nil]}
    else
      Rails.logger.error "QB Auth Falló -> #{params[:strUserName]}"
      render soap: {authRet: ["", "nvu"]}
    end
  end

  def server_version
    render soap: {serverVersionRet: ""}
  end

  def client_version
    render soap: {clientVersionRet: ""}
  end

  def send_request_xml
    render soap: {sendRequestXMLRet: ""}
  end

  def receive_response_xml
    render soap: {receiveResponseXMLRet: 100}
  end

  def connection_error
    render soap: {connectionErrorRet: "done"}
  end

  def close_connection
    render soap: {closeConnectionRet: "OK"}
  end
end
