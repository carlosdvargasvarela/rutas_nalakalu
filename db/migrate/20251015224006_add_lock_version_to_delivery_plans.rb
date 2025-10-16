class AddLockVersionToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plans, :lock_version, :integer, default: 0, null: false
  end
end
