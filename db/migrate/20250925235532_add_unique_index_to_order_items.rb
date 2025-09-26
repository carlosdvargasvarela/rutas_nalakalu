# rails generate migration AddUniqueIndexToOrderItems
class AddUniqueIndexToOrderItems < ActiveRecord::Migration[7.2]
  def change
    # Agregar índice único para evitar duplicados de producto en el mismo pedido
    add_index :order_items, [ :order_id, :product ], unique: true, name: 'index_order_items_on_order_and_product_unique'
  end
end
