# db/migrate/20241215120000_add_load_status_to_delivery_plans.rb
class AddLoadStatusToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plans, :load_status, :integer, default: 0, null: false
    add_index :delivery_plans, :load_status
  end
end
