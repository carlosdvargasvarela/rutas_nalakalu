class EditUniqueIndexToDeliveries < ActiveRecord::Migration[7.2]
  def change
    remove_index :deliveries, name: 'index_deliveries_on_order_date_address_unique', if_exists: true

    add_index :deliveries,
              [ :order_id, :delivery_date, :delivery_address_id, :status ],
              unique: true,
              name: 'index_deliveries_on_order_date_address_archived_unique'
  end
end
