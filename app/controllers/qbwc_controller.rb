# app/controllers/qbwc_controller.rb
class QbwcController < ApplicationController
  # Le dice a Rails que este es un servicio SOAP
  soap_service namespace: "urn:qbwc"

  # Paso 1: Autenticación
  # El Web Connector envía su usuario y contraseña
  soap_action "authenticate",
    args: {strUserName: :string, strPassword: :string},
    return: [:string, :string]

  def authenticate
    # Por ahora definiremos estos en variables de entorno en Heroku más adelante
    # QBWC_USER y QBWC_PASSWORD
    valid_user = ENV["QB_USER"]
    valid_pass = ENV["QB_PASS"]

    if params[:strUserName] == valid_user && params[:strPassword] == valid_pass
      # Retornamos un token de sesión (puede ser cualquier cosa aleatoria)
      # El segundo valor vacío significa que usaremos la base de datos de QB abierta
      render soap: [SecureRandom.uuid, ""]
    else
      # "nvu" significa Not Valid User
      render soap: ["nvu", ""]
    end
  end

  # Paso 2: Control de errores
  soap_action "connectionError",
    args: {ticket: :string, hresult: :string, message: :string},
    return: :string
  def connectionError
    render soap: "done"
  end

  # Paso 3: Cerrar sesión
  soap_action "closeConnection",
    args: {ticket: :string},
    return: :string
  def closeConnection
    render soap: "OK"
  end

  # Paso 4: El Web Connector pregunta "¿Qué hago?"
  soap_action "sendRequestXML",
    args: {ticket: :string, strHCPonse: :string, strCompanyFileName: :string, qbXMLCountry: :string, qbXMLMajorVers: :int, qbXMLMinorVers: :int},
    return: :string

  def sendRequestXML
    # Aquí es donde ocurre la magia.
    # Si es la primera vez que pregunta en esta sesión, le mandamos el pedido de datos.
    # Si ya terminamos, mandamos un string vacío para cerrar.

    # Por ahora, vamos a enviarle SIEMPRE la petición para probar.
    render soap: build_sales_order_query
  end

  # Paso 5: El Web Connector trae los datos de QuickBooks y nos los entrega
  soap_action "receiveResponseXML",
    args: {ticket: :string, response: :string, hresult: :string, message: :string},
    return: :int

  def receiveResponseXML
    # Aquí recibimos el XML gigante con todas las órdenes.
    xml_data = params[:response]

    # Encolamos un Job para procesar esto en background para no trabar la conexión
    # Pero por ahora solo lo pondremos en el log para ver que llegue
    Rails.logger.info "--- DATOS RECIBIDOS DE QUICKBOOKS ---"

    # Retornamos 100 para decir que terminamos (o un número menor si queremos más datos)
    render soap: 100
  end

  private

  def build_sales_order_query
    # Este es el lenguaje que entiende QuickBooks (qbXML)
    # Le pedimos SalesOrders que hayan sido modificadas recientemente
    # O podrías pedir de una fecha específica
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <?qbxml version="13.0"?>
      <QBXML>
        <QBXMLMsgsRq onError="stopOnError">
          <SalesOrderQueryRq requestID="1">
            <MaxReturned>50</MaxReturned>
            <OwnerID>0</OwnerID>
          </SalesOrderQueryRq>
        </QBXMLMsgsRq>
      </QBXML>
    XML
  end
end
