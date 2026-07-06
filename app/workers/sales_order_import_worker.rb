class SalesOrderImportWorker < QBWC::Worker
  def requests(job, session, data)
    return nil if data && data["done"]

    from_date = AppSetting.get(
      "qb_sync_from_date",
      default: 1.days.ago.strftime("%Y-%m-%dT00:00:00")
    )

    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <?qbxml version="13.0"?>
      <QBXML>
        <QBXMLMsgsRq onError="stopOnError">
          <SalesOrderQueryRq requestID="1" iterator="Start">
            <MaxReturned>100</MaxReturned>
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
      Rails.logger.info "SalesOrderImportWorker: Recibidas #{plain_payload.size} órdenes de QB."
      ProcessQuickbooksXmlJob.perform_async(plain_payload)
    end

    remaining = response.dig("xml_attributes", "iteratorRemainingCount").to_i
    # ponytail: 5 min overlap covers clock skew/in-flight edits; ProcessQuickbooksXmlJob
    # dedupes via qb_updated_at so re-seeing a few orders is harmless.
    AppSetting.set("qb_sync_from_date", 5.minutes.ago.strftime("%Y-%m-%dT%H:%M:%S")) if remaining.zero?

    {"done" => remaining.zero?}
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
