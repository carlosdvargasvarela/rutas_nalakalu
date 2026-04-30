# app/models/client_note.rb
class ClientNote < ApplicationRecord
  belongs_to :client
  belongs_to :user

  enum :category, {
    general: 0,
    logistics: 1,
    communication: 2,
    behavior: 3,
    warning: 4
  }

  validates :body, presence: true, length: {minimum: 5, maximum: 1000}
  validates :category, presence: true

  scope :pinned_first, -> { order(pinned: :desc, created_at: :desc) }
  scope :pinned, -> { where(pinned: true) }
  scope :recent, -> { order(created_at: :desc) }

  CATEGORY_LABELS = {
    "general" => "General",
    "logistics" => "Logística",
    "communication" => "Comunicación",
    "behavior" => "Comportamiento",
    "warning" => "Alerta"
  }.freeze

  CATEGORY_COLORS = {
    "general" => "secondary",
    "logistics" => "primary",
    "communication" => "success",
    "behavior" => "warning",
    "warning" => "danger"
  }.freeze

  CATEGORY_ICONS = {
    "general" => "bi-chat-text",
    "logistics" => "bi-truck",
    "communication" => "bi-telephone",
    "behavior" => "bi-person-exclamation",
    "warning" => "bi-exclamation-triangle-fill"
  }.freeze

  CATEGORY_RAW_COLORS = {
    "general" => "#6c757d",
    "logistics" => "#0d6efd",
    "communication" => "#198754",
    "behavior" => "#ffc107",
    "warning" => "#dc3545"
  }.freeze

  def category_style
    color = CATEGORY_RAW_COLORS[category] || "#6c757d"
    "background-color: #{color}1a; color: #{color}; border: 1px solid #{color}33;"
  end

  def category_label
    CATEGORY_LABELS[category] || category.humanize
  end

  def category_color
    CATEGORY_COLORS[category] || "secondary"
  end

  def category_icon
    CATEGORY_ICONS[category] || "bi-chat-text"
  end
end
