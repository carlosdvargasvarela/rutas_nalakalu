class AddSendNotificationsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :send_notifications, :boolean, default: false, null: false
  end
end