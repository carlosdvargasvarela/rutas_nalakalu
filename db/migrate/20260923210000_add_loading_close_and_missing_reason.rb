class AddLoadingCloseAndMissingReason < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_items, :missing_reason, :string
    add_column :delivery_plans, :load_closed_at, :datetime
    # Sin foreign_key: en SQLite agregarla reconstruye la tabla y el ON DELETE CASCADE
    # de delivery_plan_assignments/plan_events borraría sus filas.
    add_reference :delivery_plans, :load_closed_by, index: true
  end
end
