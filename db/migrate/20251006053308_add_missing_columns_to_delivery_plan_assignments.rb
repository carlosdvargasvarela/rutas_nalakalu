class AddMissingColumnsToDeliveryPlanAssignments < ActiveRecord::Migration[7.2]
  def change
    # enum status que el modelo usa
    add_column :delivery_plan_assignments, :status, :integer, default: 0, null: false unless column_exists?(:delivery_plan_assignments, :status)

    # timestamps de flujo
    add_column :delivery_plan_assignments, :started_at, :datetime unless column_exists?(:delivery_plan_assignments, :started_at)
    add_column :delivery_plan_assignments, :completed_at, :datetime unless column_exists?(:delivery_plan_assignments, :completed_at)

    # notas del conductor
    add_column :delivery_plan_assignments, :driver_notes, :text unless column_exists?(:delivery_plan_assignments, :driver_notes)

    # índice opcional para status (ya lo tenías antes)
    add_index :delivery_plan_assignments, :status unless index_exists?(:delivery_plan_assignments, :status)
  end
end
