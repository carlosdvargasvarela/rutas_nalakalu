# app/models/concerns/has_display_status.rb
# Traduce el enum `status` del modelo a una etiqueta en español. El modelo
# que incluye este concern debe definir la constante DISPLAY_STATUS_LABELS
# (hash string => string) — mismo patrón que EventLog#label con
# ACTION_LABELS, solo que acá cada modelo tiene su propio mapeo porque los
# enums de status (y sus traducciones) son distintos entre sí.
module HasDisplayStatus
  extend ActiveSupport::Concern

  def display_status
    self.class::DISPLAY_STATUS_LABELS[status] || status.to_s.humanize
  end
end
