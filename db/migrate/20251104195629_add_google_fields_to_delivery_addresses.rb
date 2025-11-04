# db/migrate/20251104120000_add_google_fields_to_delivery_addresses.rb
class AddGoogleFieldsToDeliveryAddresses < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_addresses, :place_id, :string
    add_column :delivery_addresses, :normalized_address, :string
    add_column :delivery_addresses, :geocode_quality, :string

    add_index :delivery_addresses, :place_id
  end
end