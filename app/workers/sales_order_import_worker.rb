class SalesOrderImportWorker < QBWC::Worker
  # 1. Definimos la petición a QuickBooks
  def requests(job, session, data)
    {
      sales_order_query_rq: {
        xml_attributes: {"requestID" => "1"},
        max_returned: 100, # Ajusta según necesites
        include_line_items: true
      }
    }
  end

  # 2. Recibimos la respuesta CRUDA (sin parsear para evitar el error 0,5)
  def handle_response(response, session, job, request, data)
    # response aquí es un String XML porque pusimos should_parse_response: false en el job

    if response.present?
      Rails.logger.info "SalesOrderImportWorker: XML recibido, enviando a Sidekiq..."

      # Enviamos el XML a un Job de Sidekiq para procesarlo fuera del ciclo de QBWC
      ProcessQuickbooksXmlJob.perform_async(response)
    else
      Rails.logger.warn "SalesOrderImportWorker: Se recibió una respuesta vacía."
    end
  end

  # Configuración para que no intente parsear y no falle con BigDecimal
  def should_parse_response
    false
  end
end
