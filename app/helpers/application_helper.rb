# app/helpers/application_helper.rb
module ApplicationHelper
  # Variantes válidas de Bootstrap 5 para badges
  BOOTSTRAP_BADGE_VARIANTS = %w[primary secondary success danger warning info light dark].freeze

  def normalize_badge_color(color)
    c = color.to_s.strip
    return "secondary" if c.blank?
    BOOTSTRAP_BADGE_VARIANTS.include?(c) ? c : "secondary"
  end

  # Delivery: usa EXACTAMENTE tus enums
  DELIVERY_STATUS_COLORS = {
    "scheduled"         => "secondary",
    "ready_to_deliver"  => "primary",
    "in_plan"           => "primary",
    "in_route"          => "warning",
    "delivered"         => "success",
    "rescheduled"       => "info",
    "cancelled"         => "danger",
    "archived"          => "light",
    "failed"            => "danger",

    # Aliases opcionales (por si algún sitio usa español)
    "programada"        => "secondary",
    "lista"             => "info",
    "en_plan"           => "primary",
    "en_ruta"           => "warning",
    "entregada"         => "success",
    "reprogramada"      => "dark",
    "cancelada"         => "danger",
    "archivada"         => "light",
    "fallida"           => "danger"
  }.freeze

  # DeliveryItem: estados típicos en tu app
  DELIVERY_ITEM_STATUS_COLORS = {
    "pending"     => "warning",
    "confirmed"   => "primary",
    "in_plan"     => "primary",
    "in_route"    => "info",
    "delivered"   => "success",
    "rescheduled" => "dark",
    "cancelled"   => "danger",
    "failed"      => "danger"
  }.freeze

  ORDER_STATUS_COLORS = {
    "in_production"      => "secondary",
    "ready_for_delivery" => "info",
    "delivered"          => "success",
    "rescheduled"        => "dark",
    "cancelled"          => "danger"
  }.freeze

  ORDER_ITEM_STATUS_COLORS = {
    "in_production" => "secondary",
    "ready"         => "info",
    "delivered"     => "success",
    "cancelled"     => "danger",
    "missing"       => "warning"
  }.freeze

  DELIVERY_PLAN_STATUS_COLORS = {
    "draft"             => "secondary",
    "sent_to_logistics" => "info",
    "routes_created"    => "primary"
  }.freeze

  STATUS_ICONS = {
    # Delivery / DeliveryItem
    "scheduled"         => "bi-clock",
    "ready_to_deliver"  => "bi-check2-square",
    "in_plan"           => "bi-map",
    "in_route"          => "bi-truck",
    "delivered"         => "bi-check-circle",
    "rescheduled"       => "bi-arrow-repeat",
    "cancelled"         => "bi-x-circle",
    "archived"          => "bi-archive",
    "failed"            => "bi-exclamation-octagon",

    # Order / OrderItem
    "in_production"     => "bi-gear",
    "ready_for_delivery"=> "bi-box-seam",
    "ready"             => "bi-check2-circle",
    "missing"           => "bi-exclamation-triangle",

    # DeliveryPlan
    "draft"             => "bi-journal",
    "sent_to_logistics" => "bi-send",
    "routes_created"    => "bi-diagram-3"
  }.freeze

  # Métodos utilitarios de fecha/hora (ASEGURAR QUE EXISTAN)
  def format_date_dd_mm_yyyy(date)
    return "" if date.blank?
    date.strftime("%d/%m/%Y")
  end

  def format_datetime_dd_mm_yyyy_hh_mm(datetime)
    return "" if datetime.blank?
    datetime.strftime("%d/%m/%Y %H:%M")
  end

  # Métodos de color por entidad
  def delivery_status_color(status)        = normalize_badge_color(DELIVERY_STATUS_COLORS[status.to_s] || "secondary")
  def delivery_item_status_color(status)   = normalize_badge_color(DELIVERY_ITEM_STATUS_COLORS[status.to_s] || "secondary")
  def order_status_color(status)           = normalize_badge_color(ORDER_STATUS_COLORS[status.to_s] || "secondary")
  def order_item_status_color(status)      = normalize_badge_color(ORDER_ITEM_STATUS_COLORS[status.to_s] || "secondary")
  def delivery_plan_status_color(status)   = normalize_badge_color(DELIVERY_PLAN_STATUS_COLORS[status.to_s] || "secondary")

  # Deducción automática de tipo según objeto AR o símbolo
  def infer_status_type(record_or_type)
    case record_or_type
    when Delivery       then :delivery
    when DeliveryItem   then :delivery_item
    when Order          then :order
    when OrderItem      then :order_item
    when DeliveryPlan   then :delivery_plan
    when Symbol, String then record_or_type.to_sym
    else
      :delivery
    end
  end

  # Obtiene el color según tipo y status string
  def color_for_status_by_type(status_str, type_sym)
    case type_sym
    when :delivery      then delivery_status_color(status_str)
    when :delivery_item then delivery_item_status_color(status_str)
    when :order         then order_status_color(status_str)
    when :order_item    then order_item_status_color(status_str)
    when :delivery_plan then delivery_plan_status_color(status_str)
    else "secondary"
    end
  end

  # Determina si un color necesita texto oscuro para mejor contraste
  def needs_text_dark?(color)
    %w[light warning info].include?(color)
  end

  # Label del estado, priorizando display_status si existe
  def label_for_status(status_or_record, type_sym, status_str)
    if status_or_record.respond_to?(:display_status)
      status_or_record.display_status
    else
      I18n.t(
        "activerecord.attributes.#{type_sym}.statuses.#{status_str}",
        default: status_str.humanize
      )
    end
  end

  # Badge genérico con auto-detección
  def status_badge(status_or_record, type = nil, with_icon: false, classes: "")
    if status_or_record.respond_to?(:status)
      status_str = status_or_record.status.to_s
      type_sym   = infer_status_type(status_or_record)
    else
      status_str = status_or_record.to_s
      type_sym   = infer_status_type(type || :delivery)
    end

    color = color_for_status_by_type(status_str, type_sym)
    label = label_for_status(status_or_record, type_sym, status_str)

    icon_html = if with_icon
      icon_class = STATUS_ICONS[status_str]
      icon_class.present? ? content_tag(:i, "", class: "bi #{icon_class} me-1", aria: { hidden: true }) : "".html_safe
    else
      "".html_safe
    end

    css_classes = [ "badge", "bg-#{color}" ]
    css_classes << "text-dark" if needs_text_dark?(color)
    css_classes << classes if classes.present?

    content_tag(:span, class: css_classes.join(" "), title: label) do
      icon_html + label
    end
  end
end
