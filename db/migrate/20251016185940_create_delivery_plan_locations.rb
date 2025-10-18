# db/migrate/20250416000001_create_delivery_plan_locations.rb
class CreateDeliveryPlanLocations < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_plan_locations do |t|
      t.references :delivery_plan, null: false, foreign_key: true, index: true
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false
      t.float :speed
      t.float :heading
      t.float :accuracy
      t.datetime :captured_at, null: false
      t.string :source, default: 'live', null: false # 'live' o 'batch'
      t.timestamps

      t.index [ :delivery_plan_id, :captured_at ], name: 'index_locations_on_plan_and_captured_at'
    end
  end
end
