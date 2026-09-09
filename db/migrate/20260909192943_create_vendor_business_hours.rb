class CreateVendorBusinessHours < ActiveRecord::Migration[7.2]
  def change
    create_table :vendor_business_hours do |t|
      t.references :vendor, null: false, foreign_key: true
      t.integer :day_of_week, null: false # 0 = domingo .. 6 = sábado (Date#wday)
      t.time :opens_at
      t.time :closes_at
      t.boolean :closed, null: false, default: false

      t.timestamps
    end

    add_index :vendor_business_hours, [:vendor_id, :day_of_week], unique: true, name: "index_vendor_business_hours_on_vendor_and_day"
  end
end
