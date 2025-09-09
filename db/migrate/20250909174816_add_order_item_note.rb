class AddOrderItemNote < ActiveRecord::Migration[7.2]
  def change
    create_table :order_item_notes do |t|
      t.references :order_item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :closed, default: false, null: false

      t.timestamps
    end
  end
end
