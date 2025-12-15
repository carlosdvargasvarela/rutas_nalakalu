class DeliveryImportProcessJob
  include Sidekiq::Job

  def perform(import_id)
    import = DeliveryImport.find(import_id)
    import.update!(status: :importing)

    service = RouteExcelImportService.new(nil)
    success_count = 0

    import.delivery_import_rows.each do |row|
      # Solo procesar filas sin errores
      next if row.row_errors.present?

      begin
        service.process_row(row.data.symbolize_keys)
        success_count += 1
      rescue => e
        Rails.logger.error "Error procesando fila #{row.id}: #{e.message}"
        # Continúa con la siguiente fila
      end
    end

    import.update!(
      status: :finished,
      success_count: success_count
    )
  rescue => e
    Rails.logger.error "DeliveryImportProcessJob failed for import #{import_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    import.update!(
      status: :failed,
      import_errors: "Error en importación final: #{e.message}"
    )
  end
end
