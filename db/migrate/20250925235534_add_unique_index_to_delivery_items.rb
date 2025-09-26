# rails generate migration AddUniqueIndexToDeliveryItems
class AddUniqueIndexToDeliveryItems < ActiveRecord::Migration[7.2]
  def change
    # Agregar índice único para evitar duplicados de order_item en la misma entrega
    add_index :delivery_items, [ :delivery_id, :order_item_id ], unique: true, name: 'index_delivery_items_on_delivery_and_order_item_unique'
  end
end
