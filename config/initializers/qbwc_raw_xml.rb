# Sobrescribimos el método response= de QBWC::Session para evitar
# que qbxml intente parsear el XML (y falle con decimales costarricenses).
# En su lugar guardamos el XML crudo para procesarlo con Nokogiri.

module QBWC
  class Session
    attr_reader :response_xml

    def response=(xml)
      @response_xml = xml.to_s
      # NO llamamos al parser qbxml — evitamos el error BigDecimal("0,5")
    end
  end
end
