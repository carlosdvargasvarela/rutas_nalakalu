# app/controllers/delivery_imports_controller.rb
class DeliveryImportsController < ApplicationController
  def new
    # Solo renderiza la vista
  end

  def preview
    file = params[:file]
    unless file
      redirect_to new_delivery_import_path, alert: "Selecciona un archivo"
      return
    end

    begin
      spreadsheet = Roo::Spreadsheet.open(file.path)

      if spreadsheet.last_row < 2
        redirect_to new_delivery_import_path, alert: "El archivo está vacío o no tiene datos válidos."
        return
      end

      service = RouteExcelImportService.new(nil)
      @rows = []
      @validation_errors = {}

      (2..spreadsheet.last_row).each do |row_num|
        row_data = {
          delivery_date: spreadsheet.cell(row_num, "A"),
          team: spreadsheet.cell(row_num, "B"),
          order_number: spreadsheet.cell(row_num, "C")&.to_s,
          client_name: spreadsheet.cell(row_num, "D")&.to_s,
          product: spreadsheet.cell(row_num, "E")&.to_s,
          quantity: spreadsheet.cell(row_num, "F")&.to_i,
          seller_code: spreadsheet.cell(row_num, "G")&.to_s,
          place: spreadsheet.cell(row_num, "H")&.to_s,
          contact: spreadsheet.cell(row_num, "I")&.to_s,
          notes: spreadsheet.cell(row_num, "J")&.to_s,
          time_preference: spreadsheet.cell(row_num, "K")&.to_s
        }

        # Validar cada fila
        validation_errors = service.validate_row(row_data)
        if validation_errors.any?
          @validation_errors[row_num - 2] = validation_errors # Índice basado en 0 para la vista
        end

        @rows << row_data
      end

      render :preview
    rescue => e
      redirect_to new_delivery_import_path, alert: "Error al procesar el archivo: #{e.message}"
    end
  end

  def process_import
    rows = params[:rows].values
    service = RouteExcelImportService.new(nil)

    success = 0
    errors = []

    rows.each_with_index do |row, idx|
      data = row.to_unsafe_h.symbolize_keys

      # Validar antes de procesar
      validation_errors = service.validate_row(data)
      if validation_errors.any?
        errors << "Fila #{idx + 2}: #{validation_errors.join(', ')}"
        next
      end

      begin
        service.process_row(data)
        success += 1
      rescue => e
        errors << "Fila #{idx + 2}: #{e.message}"
      end
    end

    @success = success
    @errors = errors
    render :result
  end

  def template
    # Opcional: genera y envía un Excel de ejemplo
  end
end
