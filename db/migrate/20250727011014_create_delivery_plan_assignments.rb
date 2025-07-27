class CreateDeliveryPlanAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_plan_assignments do |t|
      t.references :delivery, null: false, foreign_key: true
      t.references :delivery_plan, null: false, foreign_key: true

      t.timestamps
    end
  end
end
