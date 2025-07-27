class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.string :number
      t.references :client, null: false, foreign_key: true
      t.references :seller, null: false, foreign_key: true
      t.integer :status

      t.timestamps
    end
  end
end
