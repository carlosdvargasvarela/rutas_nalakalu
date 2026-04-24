# db/migrate/YYYYMMDDHHMMSS_add_warehousing_to_deliveries.rb
class AddWarehousingToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :warehousing_until, :date
    add_index :deliveries, :warehousing_until
  end
end
