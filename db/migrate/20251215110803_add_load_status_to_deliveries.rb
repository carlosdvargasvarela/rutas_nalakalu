# db/migrate/YYYYMMDDHHMMSS_add_load_status_to_deliveries.rb
class AddLoadStatusToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :load_status, :integer, default: 0, null: false
    add_index :deliveries, :load_status
  end
end
