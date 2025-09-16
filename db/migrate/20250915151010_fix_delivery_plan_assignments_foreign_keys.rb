class FixDeliveryPlanAssignmentsForeignKeys < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :delivery_plan_assignments, :deliveries
    remove_foreign_key :delivery_plan_assignments, :delivery_plans

    add_foreign_key :delivery_plan_assignments, :deliveries, on_delete: :restrict
    add_foreign_key :delivery_plan_assignments, :delivery_plans, on_delete: :cascade
  end
end
