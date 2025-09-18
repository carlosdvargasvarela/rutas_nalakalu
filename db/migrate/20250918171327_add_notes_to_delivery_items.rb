class AddNotesToDeliveryItems < ActiveRecord::Migration[7.2]
  def change
    add_column :delivery_items, :notes, :text
  end
end
