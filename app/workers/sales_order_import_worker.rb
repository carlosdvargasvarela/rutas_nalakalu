class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    {
      sales_order_query_rq: {
        xml_attributes: {"requestID" => "1"},
        max_returned: 20,
        include_line_items: true
      }
    }
  end

  # 👇 IMPORTANTE: evitar que qbxml intente parsear automáticamente
  def should_parse_response?
    false
  end

  def handle_response(response, session, job, request, data)
    Rails.logger.info "RAW XML RESPONSE:"
    Rails.logger.info response

    # luego lo parseamos nosotros manualmente
  end
end
