class AddLockVersionToDeliveryPlanAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plan_assignments, :lock_version, :integer, default: 0, null: false
  end
end
