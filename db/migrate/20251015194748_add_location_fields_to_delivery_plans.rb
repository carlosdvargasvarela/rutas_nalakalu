class AddLocationFieldsToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plans, :current_lat, :decimal, precision: 10, scale: 6 unless column_exists?(:delivery_plans, :current_lat)
    add_column :delivery_plans, :current_lng, :decimal, precision: 10, scale: 6 unless column_exists?(:delivery_plans, :current_lng)
    add_column :delivery_plans, :last_seen_at, :datetime unless column_exists?(:delivery_plans, :last_seen_at)
    add_column :delivery_plans, :current_speed, :decimal, precision: 5, scale: 2 unless column_exists?(:delivery_plans, :current_speed)
    add_column :delivery_plans, :current_heading, :decimal, precision: 5, scale: 2 unless column_exists?(:delivery_plans, :current_heading)
    add_column :delivery_plans, :current_accuracy, :decimal, precision: 6, scale: 2 unless column_exists?(:delivery_plans, :current_accuracy)

    add_index :delivery_plans, :last_seen_at unless index_exists?(:delivery_plans, :last_seen_at)
  end
end
