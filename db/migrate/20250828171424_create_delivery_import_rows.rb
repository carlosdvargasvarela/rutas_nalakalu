class CreateDeliveryImportRows < ActiveRecord::Migration[7.2]
  def change
    create_table :delivery_import_rows do |t|
      t.references :delivery_import, null: false, foreign_key: true
      # Usar 'json' cuando esté disponible, si no 'text'
      if ActiveRecord::Base.connection.adapter_name.downcase.starts_with?("sqlite")
        t.text :data
      else
        t.jsonb :data, default: {}
      end

      t.text :errors
      t.timestamps
    end
  end
end