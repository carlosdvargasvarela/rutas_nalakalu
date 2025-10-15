class AddArchivedToDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :deliveries, :archived, :boolean, null: false, default: false unless column_exists?(:deliveries, :archived)
    add_index :deliveries, :archived unless index_exists?(:deliveries, :archived)
  end
end
