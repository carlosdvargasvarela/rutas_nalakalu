class AddIndexOnDeliveriesDeliveryDate < ActiveRecord::Migration[7.2]
  def change
    add_index :deliveries, :delivery_date unless index_exists?(:deliveries, :delivery_date)
  end
end