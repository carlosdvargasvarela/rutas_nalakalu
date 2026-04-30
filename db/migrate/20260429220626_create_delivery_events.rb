# db/migrate/20260429000001_create_delivery_events.rb
class CreateDeliveryEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_events do |t|
      t.integer :delivery_id, null: false
      t.string :action, null: false
      t.integer :actor_id
      t.text :payload
      t.datetime :created_at, null: false
    end

    add_index :delivery_events, :delivery_id
    add_index :delivery_events, :action
    add_index :delivery_events, :actor_id
    add_index :delivery_events, :created_at

    add_foreign_key :delivery_events, :deliveries, on_delete: :cascade
    add_foreign_key :delivery_events, :users, column: :actor_id, on_delete: :nullify
  end
end
