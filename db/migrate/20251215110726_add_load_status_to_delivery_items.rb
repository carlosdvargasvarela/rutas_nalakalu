# db/migrate/YYYYMMDDHHMMSS_add_load_status_to_delivery_items.rb
class AddLoadStatusToDeliveryItems < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_items, :load_status, :integer, default: 0, null: false
    add_column :delivery_items, :loaded_quantity, :integer
    add_index :delivery_items, :load_status
  end
end
