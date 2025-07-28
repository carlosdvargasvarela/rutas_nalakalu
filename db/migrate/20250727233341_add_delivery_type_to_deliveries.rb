class AddDeliveryTypeToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :delivery_type, :integer, default: 0
    add_index :deliveries, :delivery_type
  end
end