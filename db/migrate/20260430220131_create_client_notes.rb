# db/migrate/YYYYMMDDHHMMSS_create_client_notes.rb
class CreateClientNotes < ActiveRecord::Migration[7.2]
  def change
    create_table :client_notes do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :category, default: 0, null: false
      t.boolean :pinned, default: false, null: false

      t.timestamps
    end

    add_index :client_notes, :category
    add_index :client_notes, :pinned
    add_index :client_notes, [:client_id, :pinned]
  end
end
