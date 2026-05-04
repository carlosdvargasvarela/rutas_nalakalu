class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    {
      sales_order_query_rq: {
        xml_attributes: {"requestID" => "1"},
        max_returned: 50,
        include_line_items: true
      }
    }
  end

  def handle_response(response, session, job, request, data)
    raw_xml = session.response_xml

    if raw_xml.blank?
      Rails.logger.warn "SalesOrderImportWorker: XML vacío recibido."
      return
    end

    Rails.logger.info "SalesOrderImportWorker: XML recibido (#{raw_xml.bytesize} bytes), encolando job..."
    ProcessQuickbooksXmlJob.perform_async(raw_xml)
  end
end
