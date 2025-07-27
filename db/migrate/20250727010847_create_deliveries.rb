class CreateDeliveries < ActiveRecord::Migration[7.2]
  def change
    create_table :deliveries do |t|
      t.references :order, null: false, foreign_key: true
      t.references :delivery_address, null: false, foreign_key: true
      t.date :delivery_date
      t.string :contact_name
      t.string :contact_phone
      t.string :contact_id
      t.integer :status
      t.string :delivery_notes

      t.timestamps
    end
  end
end
