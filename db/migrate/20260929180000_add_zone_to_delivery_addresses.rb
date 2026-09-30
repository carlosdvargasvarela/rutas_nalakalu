class AddZoneToDeliveryAddresses < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_addresses, :province, :string
    add_column :delivery_addresses, :canton, :string
    add_column :delivery_addresses, :district, :string
  end
end
