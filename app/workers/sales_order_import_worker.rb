# app/workers/sales_order_import_worker.rb
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

  def handle_response(response, session, job, request, data)
    Rails.logger.info "SalesOrderImportWorker: respuesta recibida, procesando..."

    sales_orders = extract_sales_orders(response)

    if sales_orders.blank?
      Rails.logger.warn "SalesOrderImportWorker: no se encontraron Sales Orders en la respuesta."
      return
    end

    Rails.logger.info "SalesOrderImportWorker: #{sales_orders.size} Sales Orders recibidas."
    ProcessQuickbooksSalesOrdersJob.perform_later(sales_orders.to_json)
  end

  private

  def extract_sales_orders(response)
    # response es un Hash parseado por qbxml
    response
      .dig(:qbxml_msgs_rs, :sales_order_query_rs) || []
  rescue => e
    Rails.logger.error "SalesOrderImportWorker#extract_sales_orders error: #{e.message}"
    []
  end
end
