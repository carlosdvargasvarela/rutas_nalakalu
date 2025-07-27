class CreateOrderItems < ActiveRecord::Migration[7.2]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string :product
      t.integer :quantity
      t.text :notes
      t.integer :status

      t.timestamps
    end
  end
end
