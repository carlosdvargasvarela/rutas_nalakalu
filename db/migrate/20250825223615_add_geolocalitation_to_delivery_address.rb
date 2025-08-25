class AddGeolocalitationToDeliveryAddress < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_addresses, :latitude, :decimal, precision: 10, scale: 6
    add_column :delivery_addresses, :longitude, :decimal, precision: 10, scale: 6
    add_column :delivery_addresses, :plus_code, :string
  end
end
