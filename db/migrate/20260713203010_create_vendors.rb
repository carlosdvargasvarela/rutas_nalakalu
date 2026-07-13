class CreateVendors < ActiveRecord::Migration[7.2]
  def change
    create_table :vendors do |t|
      t.string :name, null: false

      t.timestamps
    end

    create_table :vendor_contacts do |t|
      t.references :vendor, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone
      t.boolean :is_primary, default: false, null: false

      t.timestamps
    end

    create_table :vendor_addresses do |t|
      t.references :vendor, null: false, foreign_key: true
      t.text :address
      t.string :description
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :plus_code
      t.string :place_id
      t.string :normalized_address
      t.string :geocode_quality

      t.timestamps
    end
    add_index :vendor_addresses, :place_id
  end
end
