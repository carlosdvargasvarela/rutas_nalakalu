class AddQbStandbyToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :qb_standby, :boolean, default: false, null: false
    add_column :orders, :qb_standby_reason, :string
  end
end
