# db/migrate/YYYYMMDDHHMMSS_add_confirmed_by_vendor_to_deliveries.rb
class AddConfirmedByVendorToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :confirmed_by_vendor, :boolean, default: false, null: false
    add_column :deliveries, :confirmed_by_vendor_at, :datetime

    add_index :deliveries, :confirmed_by_vendor
    add_index :deliveries, :confirmed_by_vendor_at
  end
end
