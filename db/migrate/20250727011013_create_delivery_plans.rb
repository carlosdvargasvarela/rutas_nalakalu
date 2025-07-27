class CreateDeliveryPlans < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_plans do |t|
      t.string :week
      t.integer :year
      t.integer :status

      t.timestamps
    end
  end
end
