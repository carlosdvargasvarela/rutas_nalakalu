class SalesOrderImportWorker
  def self.enqueue
    # Esto le dice a la gema: "La próxima vez que QB se conecte, pídele los Sales Orders"
    QBWC.add_job(:import_sales_orders) do
      {
        sales_order_query_rq: {
          xml_attributes: {"requestID" => "1", "maxReturned" => "10"},
          # Filtramos por fecha de modificación si quisiéramos, por ahora traemos 10
          include_line_items: true
        }
      }
    end
  end

  # Este método se ejecutará automáticamente cuando QB responda con los datos
  def self.handle_response(response, session, job)
    # Aquí es donde recibiremos el XML convertido en un Hash de Ruby
    puts "--- RESPUESTA RECIBIDA DE QUICKBOOKS ---"
    sales_orders = response["sales_order_ret"]

    # Aquí conectaremos con tu RouteExcelImportService más adelante
    Array(sales_orders).each do |so|
      Rails.logger.info "Procesando pedido: #{so["ref_number"]}"
    end
  end
end
