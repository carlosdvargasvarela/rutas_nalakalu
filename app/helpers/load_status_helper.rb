# app/helpers/load_status_helper.rb
module LoadStatusHelper
  def load_status_badge(status)
    case status.to_s
    when "unloaded", "empty"
      content_tag(:span, class: "badge bg-secondary") do
        content_tag(:i, "", class: "bi bi-circle me-1") + "Sin Cargar"
      end
    when "loaded", "all_loaded"
      content_tag(:span, class: "badge bg-success") do
        content_tag(:i, "", class: "bi bi-check-circle-fill me-1") + "Cargado"
      end
    when "missing", "some_missing"
      content_tag(:span, class: "badge bg-danger") do
        content_tag(:i, "", class: "bi bi-exclamation-triangle-fill me-1") + "Faltante"
      end
    when "partial"
      content_tag(:span, class: "badge bg-warning text-dark") do
        content_tag(:i, "", class: "bi bi-hourglass-split me-1") + "Parcial"
      end
    else
      content_tag(:span, status.to_s.humanize, class: "badge bg-info")
    end
  end
end
