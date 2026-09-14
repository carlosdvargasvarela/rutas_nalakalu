class AddIndexesForQuickbooksImportLookups < ActiveRecord::Migration[7.2]
  def change
    # El import de QuickBooks (y el de Excel, que comparte process_row) busca
    # por estas columnas en cada línea de pedido; sin índice cada find_by/
    # find_or_create_by hace un seq scan sobre orders/clients. No son únicos
    # porque ya existen duplicados en datos reales (ver auditoría del connector).
    add_index :orders, :number
    add_index :clients, :name
  end
end
