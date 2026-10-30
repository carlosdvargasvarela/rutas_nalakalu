class AddNoDefinedHoursToVendors < ActiveRecord::Migration[7.2]
  def change
    add_column :vendors, :no_defined_hours, :boolean, default: false, null: false
  end
end
