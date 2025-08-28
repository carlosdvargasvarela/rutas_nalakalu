class DeliveryImportPrepareJob
  include Sidekiq::Job

  def perform(import_id)
    import = DeliveryImport.find(import_id)
    import.update!(status: :processing)

    file = nil
    begin
      # Validación defensiva: verificar que el archivo existe
      if import.file.blank? || import.file.blob.blank?
        raise "El archivo no se adjuntó correctamente al import ##{import.id}"
      end

      # Crear archivo temporal con extensión real
      original_ext = import.file.blob.filename.extension&.downcase

      if original_ext.blank?
        raise "No se pudo detectar la extensión del archivo"
      end

      file = Tempfile.new([ "import", ".#{original_ext}" ])
      file.binmode
      file.write(import.file.download)
      file.flush

      # Detectar extensión con ActiveStorage
      ext = original_ext.to_sym

      valid_exts = %i[xlsx xls ods]
      unless valid_exts.include?(ext)
        raise "Formato de archivo no soportado: #{ext.inspect}. Formatos válidos: #{valid_exts.join(', ')}"
      end

      # Abrir hoja con Roo, forzando extensión
      spreadsheet = Roo::Spreadsheet.open(file.path, extension: ext)
      service = RouteExcelImportService.new(nil)

      # Validar contenido
      if spreadsheet.last_row.nil? || spreadsheet.last_row < 2
        raise "El archivo está vacío o no tiene datos válidos"
      end

      rows_processed = 0

      (2..spreadsheet.last_row).each do |row_num|
        data = {
          delivery_date: spreadsheet.cell(row_num, "A"),
          team: spreadsheet.cell(row_num, "B"),
          order_number: spreadsheet.cell(row_num, "C")&.to_s&.strip,
          client_name: spreadsheet.cell(row_num, "D")&.to_s&.strip,
          product: spreadsheet.cell(row_num, "E")&.to_s&.strip,
          quantity: spreadsheet.cell(row_num, "F")&.to_i,
          seller_code: spreadsheet.cell(row_num, "G")&.to_s&.strip,
          place: spreadsheet.cell(row_num, "H")&.to_s&.strip,
          contact: spreadsheet.cell(row_num, "I")&.to_s&.strip,
          notes: spreadsheet.cell(row_num, "J")&.to_s&.strip,
          time_preference: spreadsheet.cell(row_num, "K")&.to_s&.strip
        }

        # Saltar filas vacías
        next if data.values.compact.empty?

        errors = service.validate_row(data)

        DeliveryImportRow.create!(
          delivery_import: import,
          data: data,
          row_errors: errors
        )

        rows_processed += 1
      end

      if rows_processed == 0
        raise "No se encontraron filas válidas para procesar en el archivo"
      end

      import.update!(status: :ready_for_review)
      Rails.logger.info "DeliveryImportPrepareJob completed for import #{import_id}: #{rows_processed} rows processed"

    rescue => e
      Rails.logger.error "DeliveryImportPrepareJob failed for import #{import_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      import.update!(
        status: :failed,
        import_errors: "Error procesando archivo: #{e.message}"
      )
    ensure
      # Limpiar archivo temporal
      if file
        file.close
        file.unlink
      end
    end
  end
end
