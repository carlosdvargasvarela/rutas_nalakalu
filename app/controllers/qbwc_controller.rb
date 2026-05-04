class QbwcController < ActionController::Base
  include QBWC::Controller

  # Definimos las acciones SOAP que la gema necesita
  soap_action "serverVersion", args: {strVersion: :string}, return: {serverVersionRet: :string}
  soap_action "clientVersion", args: {strVersion: :string}, return: {clientVersionRet: :string}
  soap_action "authenticate", args: {strUserName: :string, strPassword: :string}, return: {authRet: :string_array}
  soap_action "sendRequestXML", args: {ticket: :string, strHWM: :string, strCompanyFileName: :string, qbXMLCountry: :string, qbXMLMajorVers: :integer, qbXMLMinorVers: :integer}, return: {sendRequestXMLRet: :string}
  soap_action "receiveResponseXML", args: {ticket: :string, response: :string, hresult: :string, message: :string}, return: {receiveResponseXMLRet: :integer}
  soap_action "connectionError", args: {ticket: :string, hresult: :string, message: :string}, return: {connectionErrorRet: :string}
  soap_action "closeConnection", args: {ticket: :string}, return: {closeConnectionRet: :string}

  # Implementación de los métodos
  def authenticate
    user = ENV.fetch("QB_USER", "admin").to_s.strip
    pass = ENV.fetch("QB_PASS", "Acesa2023").to_s.strip

    received_user = params[:strUserName].to_s.strip
    received_pass = params[:strPassword].to_s.strip

    if received_user == user && received_pass == pass
      ticket = SecureRandom.uuid
      # El formato de respuesta para authenticate en wash_out es un array dentro de un hash
      render soap: {authRet: [ticket, nil]}
    else
      Rails.logger.error "QB Auth Falló para usuario: #{received_user}"
      render soap: {authRet: ["", "nvu"]}
    end
  end

  def server_version
    render soap: {serverVersionRet: ""}
  end

  def client_version
    render soap: {clientVersionRet: ""}
  end

  def connection_error
    render soap: {connectionErrorRet: "done"}
  end

  def close_connection
    render soap: {closeConnectionRet: "OK"}
  end
end
