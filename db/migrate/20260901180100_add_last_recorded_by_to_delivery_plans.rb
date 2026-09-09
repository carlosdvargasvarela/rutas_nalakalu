class AddLastRecordedByToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_reference :delivery_plans, :last_recorded_by, null: true, foreign_key: { to_table: :users }
  end
end
