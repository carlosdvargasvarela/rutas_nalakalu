class AddApprovalToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :approved, :boolean, default: true, null: false
    add_index :deliveries, :approved
  end
end
