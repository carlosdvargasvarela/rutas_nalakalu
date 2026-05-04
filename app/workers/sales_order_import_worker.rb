class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    return nil if data && data["done"]

    # Usará la variable de Heroku que acabamos de setear
    from_date = ENV.fetch("QBWC_SYNC_FROM_DATE", 30.minutes.ago.utc.strftime("%Y-%m-%dT%H:%M:%S"))

    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <?qbxml version="13.0"?>
      <QBXML>
        <QBXMLMsgsRq onError="stopOnError">
          <SalesOrderQueryRq requestID="1">
            <MaxReturned>200</MaxReturned>
            <ModifiedDateRangeFilter>
              <FromModifiedDate>#{from_date}</FromModifiedDate>
            </ModifiedDateRangeFilter>
            <IncludeLineItems>true</IncludeLineItems>
            <OwnerID>0</OwnerID>
          </SalesOrderQueryRq>
        </QBXMLMsgsRq>
      </QBXML>
    XML
  end

  def handle_response(response, session, job, request, data)
    orders = response["sales_order_ret"]

    if orders.present?
      orders = [orders] unless orders.is_a?(Array)

      # Convertimos el objeto especial de qbxml a un Hash/Array plano para Sidekiq
      # Esto evita errores de serialización
      plain_payload = deep_to_h(orders)

      Rails.logger.info "SalesOrderImportWorker: Encolando #{plain_payload.size} órdenes para procesamiento."
      ProcessQuickbooksXmlJob.perform_async(plain_payload)
    else
      Rails.logger.info "SalesOrderImportWorker: No se encontraron órdenes modificadas desde #{ENV["QBWC_SYNC_FROM_DATE"]}"
    end

    {"done" => true}
  end

  private

  def deep_to_h(obj)
    case obj
    when Array then obj.map { |v| deep_to_h(v) }
    when Hash then obj.to_h.transform_values { |v| deep_to_h(v) }
    when BigDecimal then obj.to_s("F")
    else obj
    end
  end
end
