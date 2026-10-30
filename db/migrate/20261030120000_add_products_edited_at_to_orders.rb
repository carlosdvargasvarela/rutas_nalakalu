class AddProductsEditedAtToOrders < ActiveRecord::Migration[7.2]
  # Marca los pedidos con productos corregidos a mano: QuickBooks ya no toca sus líneas.
  def change
    add_column :orders, :products_edited_at, :datetime
  end
end
