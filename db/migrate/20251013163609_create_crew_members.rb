class CreateCrewMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :crew_members do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :id_number

      t.timestamps
    end
  end
end
