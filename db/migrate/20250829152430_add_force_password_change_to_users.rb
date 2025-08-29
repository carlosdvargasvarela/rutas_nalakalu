class AddForcePasswordChangeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :force_password_change, :boolean, default: true, null: false
  end
end
