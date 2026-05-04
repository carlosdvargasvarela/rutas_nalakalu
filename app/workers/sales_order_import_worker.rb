# app/workers/sales_order_import_worker.rb
class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    return nil if data && data["done"]

    # Hora de Costa Rica para coincidir con la PC donde está QuickBooks
    costa_rica_now = Time.find_zone("Central America").now
    default_from = costa_rica_now.beginning_of_day.strftime("%Y-%m-%dT%H:%M:%S")
    from_date = ENV.fetch("QBWC_SYNC_FROM_DATE", default_from)

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
      from_date = ENV.fetch("QBWC_SYNC_FROM_DATE", Time.find_zone("Central America").now.beginning_of_day.strftime("%Y-%m-%dT%H:%M:%S"))
      Rails.logger.info "SalesOrderImportWorker: No se encontraron órdenes modificadas desde #{from_date}"
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
