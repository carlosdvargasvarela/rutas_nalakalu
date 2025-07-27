class AddDeliveryTimePreferenceToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :delivery_time_preference, :string
  end
end