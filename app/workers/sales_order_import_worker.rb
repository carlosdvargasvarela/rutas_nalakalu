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
    # `response` puede ser String (XML crudo) o Hash (si qbxml lo parseó)
    # Normalizamos a String en ambos casos
    raw_xml = case response
    when String then response
    when Hash then response.to_s  # fallback, no debería pasar
    else response.to_s
    end

    Rails.logger.info "=== QBWC handle_response ==="
    Rails.logger.info "response.class: #{response.class}"
    Rails.logger.info "raw_xml primeros 300 chars: #{raw_xml[0..300]}"

    if raw_xml.blank? || !raw_xml.include?("SalesOrder")
      Rails.logger.warn "SalesOrderImportWorker: XML vacío o sin SalesOrders."
      return
    end

    Rails.logger.info "SalesOrderImportWorker: Encolando ProcessQuickbooksXmlJob (#{raw_xml.bytesize} bytes)"
    ProcessQuickbooksXmlJob.perform_async(raw_xml)
  end
end
