# db/migrate/YYYYMMDDHHMMSS_add_tracking_token_to_deliveries.rb
class AddTrackingTokenToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :tracking_token, :string
    add_index :deliveries, :tracking_token, unique: true
  end
end