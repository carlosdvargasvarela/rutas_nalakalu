class RenameErrorsColumnInDeliveryImports < ActiveRecord::Migration[7.2]
  def change
    rename_column :delivery_imports, :errors, :import_errors
  end
end