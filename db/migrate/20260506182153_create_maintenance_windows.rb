# db/migrate/XXXXXX_create_maintenance_windows.rb
class CreateMaintenanceWindows < ActiveRecord::Migration[7.2]
  def change
    create_table :maintenance_windows do |t|
      t.boolean :active, default: false, null: false
      t.datetime :ends_at
      t.integer :activated_by_id, null: false
      t.text :allowed_user_ids, default: "[]"
      t.string :message, default: "El sistema está en mantenimiento. Volvemos pronto."

      t.timestamps
    end

    add_foreign_key :maintenance_windows, :users, column: :activated_by_id
    add_index :maintenance_windows, :active
  end
end
