class CreateShowroomsAndUpdateDeliveries < ActiveRecord::Migration[7.2]
  def change
    create_table :showrooms do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.references :delivery_address, null: true, foreign_key: true
      t.text :order_number_prefixes, null: false, default: "[]"
      t.text :order_number_keywords, null: false, default: "[]"
      t.text :inter_sala_keywords,   null: false, default: "[]"
      t.text :product_keywords,      null: false, default: "[]"
      t.boolean :is_main, null: false, default: false
      t.timestamps
    end

    add_index :showrooms, :code, unique: true

    add_reference :deliveries, :source_showroom,      null: true, foreign_key: { to_table: :showrooms }
    add_reference :deliveries, :destination_showroom, null: true, foreign_key: { to_table: :showrooms }
  end
end
