class CreateDeliveryGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_groups do |t|
      t.string :label
      t.timestamps
    end

    create_table :delivery_group_memberships do |t|
      t.references :delivery_group, null: false, foreign_key: true
      t.references :delivery,       null: false, foreign_key: true
      t.timestamps
    end

    # Each delivery belongs to at most one group
    add_index :delivery_group_memberships, :delivery_id, unique: true,
              name: "idx_dgm_unique_delivery"
  end
end
