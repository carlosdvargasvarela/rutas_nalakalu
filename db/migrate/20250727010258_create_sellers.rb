class CreateSellers < ActiveRecord::Migration[7.2]
  def change
    create_table :sellers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :seller_code, null: false

      t.timestamps
    end
    add_index :sellers, :seller_code, unique: true
  end
end
