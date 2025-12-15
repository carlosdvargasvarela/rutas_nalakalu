class DeliveryImportsController < ApplicationController
  def new
    @import = DeliveryImport.new
  end

  def create
    # Crear el import primero
    import = current_user.delivery_imports.new(status: :pending)

    # Adjuntar el archivo ANTES de guardar
    import.file.attach(params[:delivery_import][:file])

    # Guardar con el archivo ya adjunto
    import.save!

    # Ahora sí encolar el job (el archivo ya existe)
    DeliveryImportPrepareJob.perform_async(import.id)

    redirect_to delivery_import_path(import), notice: "El archivo está siendo procesado."
  end

  def show
    @import = DeliveryImport.find(params[:id])
  end

  # PATCH /delivery_imports/:id/update_rows
  def update_rows
    import = DeliveryImport.find(params[:id])
    service = RouteExcelImportService.new(nil)
    updated_count = 0

    params[:rows].each do |id, row_params|
      row = import.delivery_import_rows.find(id)

      # Normalizar parámetros nuevos
      new_data = row_params.to_unsafe_h.transform_keys(&:to_s)

      # Mezclar con lo que ya tenía
      merged_data = row.data.merge(new_data)

      # Guardar
      row.update!(
        data: merged_data,
        row_errors: service.validate_row(merged_data.symbolize_keys)
      )

      updated_count += 1
    end

    if import.delivery_import_rows.any? { |r| r.row_errors.present? }
      redirect_to delivery_import_path(import), alert: "Se actualizaron #{updated_count} filas. Corrige los errores restantes antes de importar."
    else
      redirect_to delivery_import_path(import), notice: "Se actualizaron #{updated_count} filas correctamente. Ya puedes procesar la importación."
    end
  end

  # POST /delivery_imports/:id/process_import
  def process_import
    import = DeliveryImport.find(params[:id])

    if import.delivery_import_rows.any? { |r| r.row_errors.present? }
      redirect_to delivery_import_path(import), alert: "Debes corregir los errores antes de importar."
    else
      DeliveryImportProcessJob.perform_async(import.id)
      redirect_to delivery_import_path(import), notice: "Importación lanzada."
    end
  end

  # GET /delivery_imports/template
  def template
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Entregas") do |sheet|
      sheet.add_row ["Fecha de entrega", "Equipo", "Número de pedido", "Cliente",
        "Producto", "Cantidad", "Código de vendedor", "Dirección",
        "Contacto"]
    end
    send_data package.to_stream.read,
      filename: "plantilla_entregas.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def delivery_import_params
    params.require(:delivery_import).permit(:file)
  end
end
