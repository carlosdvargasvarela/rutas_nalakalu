# rails generate migration AddUniqueIndexToDeliveries
class AddUniqueIndexToDeliveries < ActiveRecord::Migration[7.2]
  def change
    # Agregar índice único para evitar duplicados de entrega en la misma fecha y dirección
    add_index :deliveries, [ :order_id, :delivery_date, :delivery_address_id ], unique: true, name: 'index_deliveries_on_order_date_address_unique'
  end
end
