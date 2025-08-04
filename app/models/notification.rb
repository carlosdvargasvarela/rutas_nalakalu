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
end