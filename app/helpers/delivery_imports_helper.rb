module DeliveryImportsHelper
  def humanize_column_name(col)
    translations = {
      'delivery_date' => 'Fecha Entrega',
      'team' => 'Equipo',
      'order_number' => 'Número Pedido',
      'client_name' => 'Cliente',
      'product' => 'Producto',
      'quantity' => 'Cantidad',
      'seller_code' => 'Código Vendedor',
      'place' => 'Lugar',
      'contact' => 'Contacto',
      'notes' => 'Notas',
      'time_preference' => 'Preferencia Horaria'
    }
    translations[col.to_s] || col.to_s.humanize
  end

  def required_field?(col)
    %w[delivery_date order_number client_name product quantity seller_code place].include?(col.to_s)
  end

  def field_has_errors?(field, row_errors)
    return false unless row_errors

    field_error_keywords = {
      'delivery_date' => ['fecha'],
      'order_number' => ['número', 'pedido'],
      'client_name' => ['cliente'],
      'product' => ['producto'],
      'quantity' => ['cantidad'],
      'seller_code' => ['código', 'vendedor'],
      'place' => ['lugar']
    }

    keywords = field_error_keywords[field.to_s] || []
    row_errors.any? { |error| keywords.any? { |keyword| error.downcase.include?(keyword) } }
  end

  def get_field_error_message(field, row_errors)
    return "" unless row_errors

    field_error_keywords = {
      'delivery_date' => ['fecha'],
      'order_number' => ['número', 'pedido'],
      'client_name' => ['cliente'],
      'product' => ['producto'],
      'quantity' => ['cantidad'],
      'seller_code' => ['código', 'vendedor'],
      'place' => ['lugar']
    }

    keywords = field_error_keywords[field.to_s] || []
    matching_error = row_errors.find { |error| keywords.any? { |keyword| error.downcase.include?(keyword) } }
    matching_error || row_errors.first
  end
end