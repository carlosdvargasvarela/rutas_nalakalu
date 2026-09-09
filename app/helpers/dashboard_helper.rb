# app/helpers/dashboard_helper.rb
module DashboardHelper
  ATTENTION_CATEGORIES = {
    error: {label: "Error", icon: "bi-exclamation-triangle-fill", color: "danger"},
    service: {label: "Servicio", icon: "bi-tools", color: "info"},
    repair: {label: "Reparación", icon: "bi-wrench-adjustable", color: "info"},
    sala_pickup: {label: "Sala", icon: "bi-shop", color: "danger"},
    approval: {label: "Por aprobar", icon: "bi-shield-check", color: "primary"},
    warehousing: {label: "Bodegaje", icon: "bi-building", color: "warning"},
    reschedule: {label: "Reprogramación", icon: "bi-arrow-repeat", color: "warning"}
  }.freeze

  def attention_category_info(category)
    ATTENTION_CATEGORIES.fetch(category.to_sym)
  end

  def attention_category_badge(category)
    info = attention_category_info(category)
    content_tag(:span, class: "badge bg-#{info[:color]}-subtle text-#{info[:color]}-emphasis border border-#{info[:color]}-subtle rounded-pill") do
      "#{content_tag(:i, "", class: "bi #{info[:icon]} me-1")}#{info[:label]}".html_safe
    end
  end
end
