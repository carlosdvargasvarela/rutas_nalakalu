class CreateDeliveryItems < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_items do |t|
      t.references :delivery, null: false, foreign_key: true
      t.references :order_item, null: false, foreign_key: true
      t.integer :quantity_delivered
      t.integer :status
      t.boolean :service_case, default: false

      t.timestamps
    end
  end
end
