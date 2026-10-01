class CreateQbStandbyOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :qb_standby_orders do |t|
      t.string :order_number, null: false
      t.string :qb_txn_id, null: false
      t.string :reason, null: false
      t.text :payload, null: false
      t.timestamps
    end
    add_index :qb_standby_orders, :qb_txn_id, unique: true
  end
end
