class CreateOrderContacts < ActiveRecord::Migration[7.2]
  def change
    create_table :order_contacts do |t|
      t.references :order, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone
      t.boolean :is_primary, null: false, default: false

      t.timestamps
    end
  end
end
