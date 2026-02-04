class AddRecordedAtToDeliveryPlanLocations < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plan_locations, :recorded_at, :datetime
    add_index :delivery_plan_locations, :recorded_at
  end
end
