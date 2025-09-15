# db/migrate/20250915235900_add_truck_to_delivery_plans.rb
class AddTruckToDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_plans, :truck, :integer
  end
end
