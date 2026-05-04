class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    # Si ya procesamos, no enviamos más requests
    return nil if data && data[:done]

    {
      sales_order_query_rq: {
        xml_attributes: {"requestID" => "1"},
        max_returned: 50,
        include_line_items: true
      }
    }
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

    # 👇 CLAVE: marcar como done para que requests() retorne nil
    {done: true}
  end
end
