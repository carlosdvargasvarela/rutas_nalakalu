class AddDriverIdToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plans, :driver_id, :integer
    add_index :delivery_plans, :driver_id
    add_foreign_key :delivery_plans, :users, column: :driver_id
  end
end