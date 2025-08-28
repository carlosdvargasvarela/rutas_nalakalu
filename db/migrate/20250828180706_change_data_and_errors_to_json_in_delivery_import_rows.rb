class ChangeDataAndErrorsToJsonInDeliveryImportRows < ActiveRecord::Migration[7.2]
  def up
    if ActiveRecord::Base.connection.adapter_name.downcase.starts_with?("postgresql")
      change_column :delivery_import_rows, :data, :jsonb, using: 'data::jsonb', default: {}
      change_column :delivery_import_rows, :errors, :jsonb, using: 'errors::jsonb', default: []
    else
      # SQLite (dev/test): mantener como TEXT pero agregar defaults
      change_column :delivery_import_rows, :data, :text, default: "{}"
      change_column :delivery_import_rows, :errors, :text, default: "[]"
    end
  end

  def down
    change_column :delivery_import_rows, :data, :text
    change_column :delivery_import_rows, :errors, :text
  end
end