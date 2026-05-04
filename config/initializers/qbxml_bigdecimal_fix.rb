# config/initializers/qbxml_bigdecimal_fix.rb
# Fix para qbxml-1.0.0: QuickBooks Costa Rica envía decimales con coma (ej: "0,5")
# BigDecimal() de Ruby moderno lanza excepción con ese formato.

Rails.application.config.after_initialize do
  if defined?(Qbxml::Types::TYPES)
    decimal_fix = ->(v) {
      begin
        BigDecimal(v.to_s.tr(",", "."))
      rescue
        BigDecimal(0)
      end
    }

    Qbxml::Types::TYPES.merge!(
      "AMTTYPE" => decimal_fix,
      "PRICETYPE" => decimal_fix,
      "QUANTYPE" => decimal_fix,
      "PERCENTTYPE" => decimal_fix,
      "FLOATTYPE" => decimal_fix
    )

    Rails.logger.info "qbxml_bigdecimal_fix: patch aplicado correctamente."
  else
    Rails.logger.warn "qbxml_bigdecimal_fix: Qbxml::Types::TYPES no encontrado, patch NO aplicado."
  end
end
