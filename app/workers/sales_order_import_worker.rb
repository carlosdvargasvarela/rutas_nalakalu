class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    return nil if data && data[:done]

    # XML crudo — evitamos que la gema intente parsear/construir QBXML
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <?qbxml version="13.0"?>
      <QBXML>
        <QBXMLMsgsRq onError="stopOnError">
          <SalesOrderQueryRq requestID="1">
            <MaxReturned>100</MaxReturned>
            <IncludeLineItems>true</IncludeLineItems>
            <IncludeLinkedTxns>false</IncludeLinkedTxns>
            <OwnerID>0</OwnerID>
          </SalesOrderQueryRq>
        </QBXMLMsgsRq>
      </QBXML>
    XML
  end

  def handle_response(response, session, job, request, data)
    raw_xml = response.to_s

    Rails.logger.info "=== QBWC handle_response ==="
    Rails.logger.info "response.class: #{response.class}"
    Rails.logger.info "raw_xml primeros 300 chars: #{raw_xml[0..300]}"

    if raw_xml.blank? || !raw_xml.include?("SalesOrder")
      Rails.logger.warn "SalesOrderImportWorker: XML vacío o sin SalesOrders."
    else
      Rails.logger.info "SalesOrderImportWorker: Encolando ProcessQuickbooksXmlJob (#{raw_xml.bytesize} bytes)"
      ProcessQuickbooksXmlJob.perform_async(raw_xml)
    end

    {done: true}
  end
end
