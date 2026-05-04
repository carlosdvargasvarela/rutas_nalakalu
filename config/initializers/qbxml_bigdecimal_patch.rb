# Parche para qbxml 1.0.0: QuickBooks Desktop (Costa Rica) puede devolver
# decimales con coma ("0,5") que BigDecimal() no acepta en Ruby 3.x.
# Este patch normaliza la coma a punto antes del casteo.

require "bigdecimal"

module Qbxml
  module Types
    BIGDECIMAL_CAST = proc do |d|
      if d
        normalized = d.to_s.tr(",", ".")
        BigDecimal(normalized)
      else
        BigDecimal(0)
      end
    end
  end
end
