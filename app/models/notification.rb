# app/models/notification.rb
class Notification < ApplicationRecord
  has_paper_trail

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :message, presence: true

  scope :unread, -> { where(read: false) }
  scope :recent, -> { order(created_at: :desc) }

  def mark_as_read!
    update!(read: true)
  end

  def mark_as_unread!
    update!(read: false)
  end

  def target_path
    helpers = Rails.application.routes.url_helpers

    case notifiable
    when Delivery
      helpers.delivery_path(notifiable)
    when Order
      helpers.order_path(notifiable)
    when DeliveryItem
      notifiable.delivery.present? ? helpers.delivery_path(notifiable.delivery, anchor: "item-#{notifiable.id}") : helpers.root_path
    when OrderItem
      notifiable.order.present? ? helpers.order_path(notifiable.order, anchor: "order-item-#{notifiable.id}") : helpers.root_path
    else
      helpers.root_path
    end
  end
end
