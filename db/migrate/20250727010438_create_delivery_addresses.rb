class CreateDeliveryAddresses < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_addresses do |t|
      t.references :client, null: false, foreign_key: true
      t.text :address
      t.string :description

      t.timestamps
    end
  end
end
