class FixDriverSessionsForeignKeys < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :driver_sessions, :delivery_plans
    add_foreign_key :driver_sessions, :delivery_plans, on_delete: :cascade
  end
end
