class RenameErrorsColumnInDeliveryImportRows < ActiveRecord::Migration[7.2]
  def change
    rename_column :delivery_import_rows, :errors, :row_errors
  end
end