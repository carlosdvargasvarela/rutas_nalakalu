class Notification < ApplicationRecord
  has_paper_trail

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :message, presence: true

  scope :unread, -> { where(read: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(notification_type: type) if type.present? }

  # Lógica visual centralizada
  TYPES = {
    "delivery" => {icon: "bi-truck", color: "primary", label: "Entregas"},
    "order" => {icon: "bi-cart-check", color: "success", label: "Pedidos"},
    "system" => {icon: "bi-cpu", color: "secondary", label: "Sistema"},
    "alert" => {icon: "bi-exclamation-triangle", color: "danger", label: "Alertas"}
  }.freeze

  def type_config
    TYPES[notification_type] || {icon: "bi-bell", color: "info", label: notification_type&.humanize}
  end

  def mark_as_read!
    update!(read: true)
  end

  def target_path
    helpers = Rails.application.routes.url_helpers
    case notifiable
    when Delivery then helpers.delivery_path(notifiable)
    when Order then helpers.order_path(notifiable)
    when DeliveryItem then notifiable.delivery ? helpers.delivery_path(notifiable.delivery, anchor: "item-#{notifiable.id}") : helpers.root_path
    when OrderItem then notifiable.order ? helpers.order_path(notifiable.order, anchor: "item-#{notifiable.id}") : helpers.root_path
    else helpers.root_path
    end
  rescue
    "/"
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "message", "notification_type", "read", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["notifiable", "user"]
  end
end
