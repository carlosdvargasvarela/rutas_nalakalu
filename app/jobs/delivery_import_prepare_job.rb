# app/jobs/delivery_import_prepare_job.rb
class DeliveryImportPrepareJob
  include Sidekiq::Job

  def perform(import_id)
    import = DeliveryImport.find(import_id)
    import.update!(status: :processing)

    file = nil
    begin
      if import.file.blank? || import.file.blob.blank?
        raise "El archivo no se adjuntó correctamente al import ##{import.id}"
      end

      original_ext = import.file.blob.filename.extension&.downcase
      raise "No se pudo detectar la extensión del archivo" if original_ext.blank?

      file = Tempfile.new([ "import", ".#{original_ext}" ])
      file.binmode
      file.write(import.file.download)
      file.flush

      ext = original_ext.to_sym
      valid_exts = %i[xlsx xls ods]
      unless valid_exts.include?(ext)
        raise "Formato de archivo no soportado: #{ext.inspect}. Formatos válidos: #{valid_exts.join(', ')}"
      end

      spreadsheet = Roo::Spreadsheet.open(file.path, extension: ext)
      service = RouteExcelImportService.new(nil)

      if spreadsheet.last_row.nil? || spreadsheet.last_row < 2
        raise "El archivo está vacío o no tiene datos válidos"
      end

      raw_rows = []

      (2..spreadsheet.last_row).each do |row_num|
        data = {
          delivery_date:   spreadsheet.cell(row_num, "A"),
          team:            norm_str(spreadsheet.cell(row_num, "B")),
          order_number:    norm_str(spreadsheet.cell(row_num, "C")),
          client_name:     norm_str(spreadsheet.cell(row_num, "D")),
          product:         norm_str(spreadsheet.cell(row_num, "E")),
          quantity:        spreadsheet.cell(row_num, "F").to_i,
          seller_code:     norm_str(spreadsheet.cell(row_num, "G")),
          place:           norm_str(spreadsheet.cell(row_num, "H")),
          contact:         norm_str(spreadsheet.cell(row_num, "I")),
          notes:           norm_str(spreadsheet.cell(row_num, "J")),
          time_preference: norm_str(spreadsheet.cell(row_num, "K"))
        }

        next if data.values.compact.empty?
        raw_rows << data
      end

      grouped = raw_rows.group_by { |row| [ row[:order_number], row[:product], row[:delivery_date], row[:place] ] }

      rows_processed = 0

      grouped.each do |_key, rows|
        merged_data = rows.first.dup
        merged_data[:quantity] = rows.sum { |r| r[:quantity].to_i }

        all_notes = rows.map { |r| r[:notes] }.compact_blank.uniq
        merged_data[:notes] = all_notes.join("; ") if all_notes.any?

        errors = service.validate_row(merged_data)

        DeliveryImportRow.create!(
          delivery_import: import,
          data: merged_data,
          row_errors: errors
        )

        rows_processed += 1
      end

      raise "No se encontraron filas válidas para procesar en el archivo" if rows_processed == 0

      import.update!(status: :ready_for_review)
      Rails.logger.info "DeliveryImportPrepareJob completed for import #{import_id}: #{rows_processed} rows processed"

    rescue => e
      Rails.logger.error "DeliveryImportPrepareJob failed for import #{import_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      import.update!(status: :failed, import_errors: "Error procesando archivo: #{e.message}")
    ensure
      file&.close
      file&.unlink
    end
  end

  private

  def norm_str(v)
    v.to_s.strip.presence
  end
end
