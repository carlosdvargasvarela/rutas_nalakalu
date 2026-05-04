# config/initializers/qbxml_bigdecimal_fix.rb
# Fix para qbxml-1.0.0: QuickBooks Costa Rica envía decimales con coma (ej: "0,5")
# Usamos prepend sobre Qbxml::Hash para interceptar el typecast ANTES del BigDecimal.

module QbxmlBigDecimalPatch
  private

  def typecast(value, type)
    # Normalizamos coma decimal -> punto para todos los tipos numéricos
    if %w[AMTTYPE PRICETYPE QUANTYPE PERCENTTYPE FLOATTYPE].include?(type)
      value = value.to_s.tr(",", ".")
    end
    super
  rescue ArgumentError => e
    # Fallback: si aún falla, retornamos 0 en lugar de explotar
    Rails.logger.warn "QbxmlBigDecimalPatch: typecast falló para value=#{value.inspect} type=#{type}: #{e.message}"
    0
  end
end

# Esperamos a que la gema esté cargada antes de parchear
Rails.application.config.to_prepare do
  if defined?(Qbxml::Hash)
    Qbxml::Hash.prepend(QbxmlBigDecimalPatch)
    Rails.logger.info "QbxmlBigDecimalPatch: prepend aplicado sobre Qbxml::Hash."
  else
    Rails.logger.warn "QbxmlBigDecimalPatch: Qbxml::Hash no encontrado, patch NO aplicado."
  end
end
