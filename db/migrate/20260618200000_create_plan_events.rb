class CreatePlanEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :plan_events do |t|
      t.integer :delivery_plan_id, null: false
      t.string :action, null: false
      t.integer :actor_id
      t.text :payload
      t.datetime :created_at, null: false
    end

    add_index :plan_events, :delivery_plan_id
    add_index :plan_events, :action
    add_index :plan_events, :actor_id
    add_index :plan_events, :created_at

    add_foreign_key :plan_events, :delivery_plans, on_delete: :cascade
    add_foreign_key :plan_events, :users, column: :actor_id, on_delete: :nullify
  end
end
