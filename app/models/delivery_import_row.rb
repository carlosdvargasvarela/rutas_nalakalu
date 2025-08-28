class DeliveryImportRow < ApplicationRecord
  belongs_to :delivery_import

  # Para SQLite serializamos y parseamos manualmente
  # En Postgres jsonb ya funciona nativo
  if ActiveRecord::Base.connection.adapter_name.downcase.starts_with?("sqlite")
    serialize :data, coder: JSON
    serialize :row_errors, coder: JSON
  end
end