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
    orders = Array.wrap(response["sales_order_ret"])

    Rails.logger.info "=== QB: #{orders.count} Sales Orders recibidos ==="

    orders.each do |so|
      Rails.logger.info(
        "Pedido: #{so["ref_number"]} | " \
        "Cliente: #{so.dig("customer_ref", "full_name")} | " \
        "Entrega: #{so["due_date"]}"
      )
    end

    QBWC.delete_job(job)
  end
end
