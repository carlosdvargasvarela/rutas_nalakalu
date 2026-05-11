class AddSalaPickupRequestedToDeliveryItems < ActiveRecord::Migration[7.1]
  def change
    add_column :delivery_items, :sala_pickup_requested, :boolean, default: false, null: false
  end
end
