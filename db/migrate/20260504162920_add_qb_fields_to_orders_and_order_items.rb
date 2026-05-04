class AddQbFieldsToOrdersAndOrderItems < ActiveRecord::Migration[7.2]
  def change
    # Guardamos el ID único del Sales Order de QuickBooks
    add_column :orders, :qb_txn_id, :string
    add_index :orders, :qb_txn_id, unique: true

    # Guardamos el ID único de la línea (producto) del pedido
    add_column :order_items, :qb_line_id, :string
    add_index :order_items, :qb_line_id, unique: true

    # También agregamos un campo para guardar cuándo fue la última vez
    # que ese pedido se actualizó desde QuickBooks
    add_column :orders, :qb_updated_at, :datetime
  end
end
