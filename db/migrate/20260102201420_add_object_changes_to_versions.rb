# db/migrate/XXXXXX_add_object_changes_to_versions.rb
class AddObjectChangesToVersions < ActiveRecord::Migration[7.2]
  def change
    add_column :versions, :object_changes, :text, limit: 1073741823
  end
end
