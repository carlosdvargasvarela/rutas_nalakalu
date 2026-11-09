class DeliveryImportsController < ApplicationController
  def new
    authorize DeliveryImport
    @import = DeliveryImport.new
  end

  def create
    authorize DeliveryImport, :create?
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
    authorize DeliveryImport
    @import = DeliveryImport.find(params[:id])
  end

  # PATCH /delivery_imports/:id/update_rows
  def update_rows
    authorize DeliveryImport
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
    authorize DeliveryImport
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
    authorize DeliveryImport, :create?
    send_data self.class.template_package.to_stream.read,
      filename: "plantilla_entregas.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # Columnas A–K tal como las lee DeliveryImportPrepareJob (no cambiar el orden).
  def self.template_package
    package = Axlsx::Package.new
    wb = package.workbook
    head = wb.styles.add_style(b: true, bg_color: "DDDDDD", border: {style: :thin, color: "999999"})
    date = wb.styles.add_style(format_code: "dd/mm/yyyy")
    wb.add_worksheet(name: "Entregas") do |sheet|
      sheet.add_row ["Fecha de entrega", "Equipo", "Número de pedido", "Cliente",
        "Producto", "Cantidad", "Código de vendedor", "Dirección",
        "Contacto", "Notas", "Preferencia horaria"], style: head
      sheet.add_row [Date.current + 7, "", "PED-0001", "Cliente Ejemplo S.A.",
        "Sofá 3 plazas gris", 1, "V01", "San José, Escazú, 200m norte del parque",
        "María Pérez / 8888-8888", "Ejemplo: borrar esta fila", "8am - 12md"],
        style: [date] + [nil] * 10
      sheet.column_widths 16, 10, 18, 26, 30, 10, 18, 40, 26, 30, 20
      sheet.sheet_view.pane { |p| p.top_left_cell = "A2"; p.state = :frozen; p.y_split = 1 }
    end
    wb.add_worksheet(name: "Instrucciones") do |sheet|
      [["Columna", "Obligatorio", "Descripción"],
        ["Fecha de entrega", "Sí", "Formato fecha (dd/mm/aaaa)."],
        ["Equipo", "No", "Escribir C.S si es un caso de servicio."],
        ["Número de pedido", "Sí", "Una fila por producto; repetir el número en cada fila del mismo pedido."],
        ["Cliente", "Sí", "Nombre del cliente. Se crea si no existe."],
        ["Producto", "Sí", "Descripción del producto."],
        ["Cantidad", "Sí", "Número entero mayor a 0. Filas repetidas (mismo pedido, producto, fecha y dirección) se suman."],
        ["Código de vendedor", "Sí", "Debe existir en Rutas."],
        ["Dirección", "Sí", "Lugar de entrega."],
        ["Contacto", "No", "Nombre / teléfono (separados por / o -)."],
        ["Notas", "No", "Notas del producto."],
        ["Preferencia horaria", "No", "Horario preferido de entrega."]].each_with_index do |row, i|
        sheet.add_row row, style: (i.zero? ? head : nil)
      end
      sheet.column_widths 22, 12, 90
    end
    package
  end

  private

  def delivery_import_params
    params.require(:delivery_import).permit(:file)
  end
end
