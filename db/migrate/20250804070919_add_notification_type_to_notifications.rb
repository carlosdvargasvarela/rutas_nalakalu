class AddNotificationTypeToNotifications < ActiveRecord::Migration[7.2]
  def change
    add_column :notifications, :notification_type, :string
  end
end
