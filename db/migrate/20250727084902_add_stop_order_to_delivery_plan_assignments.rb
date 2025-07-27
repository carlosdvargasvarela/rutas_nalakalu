class AddStopOrderToDeliveryPlanAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plan_assignments, :stop_order, :integer
  end
end
