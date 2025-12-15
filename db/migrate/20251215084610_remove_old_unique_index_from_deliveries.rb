class RemoveOldUniqueIndexFromDeliveries < ActiveRecord::Migration[7.2]
  def change
    remove_index :deliveries, name: "index_deliveries_on_order_date_address_archived_unique"
  end
end
