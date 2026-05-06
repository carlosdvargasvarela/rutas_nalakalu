class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    return nil if data && data["done"]

    from_date = ENV.fetch(
      "QBWC_SYNC_FROM_DATE",
      2.days.ago.strftime("%Y-%m-%dT00:00:00")
    )

    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <?qbxml version="13.0"?>
      <QBXML>
        <QBXMLMsgsRq onError="stopOnError">
          <SalesOrderQueryRq requestID="1">
            <MaxReturned>50</MaxReturned>
            <ModifiedDateRangeFilter>
              <FromModifiedDate>#{from_date}</FromModifiedDate>
            </ModifiedDateRangeFilter>
            <IncludeLineItems>true</IncludeLineItems>
            <IncludeLinkedTxns>false</IncludeLinkedTxns>
            <OwnerID>0</OwnerID>
          </SalesOrderQueryRq>
        </QBXMLMsgsRq>
      </QBXML>
    XML
  end

  def handle_response(response, session, job, request, data)
    orders = response["sales_order_ret"]

    if orders.present?
      orders = Array.wrap(orders)
      plain_payload = deep_to_h(orders)
      Rails.logger.info "SalesOrderImportWorker: Encolando #{plain_payload.size} órdenes para procesamiento."
      ProcessQuickbooksXmlJob.perform_async(plain_payload)
    else
      Rails.logger.info "SalesOrderImportWorker: No se encontraron órdenes modificadas desde #{2.days.ago.strftime("%Y-%m-%dT00:00:00")}"
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
