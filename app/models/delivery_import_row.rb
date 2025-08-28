class DeliveryImportRow < ApplicationRecord
  belongs_to :delivery_import

  # Serializamos siempre para que tanto SQLite como Postgres
  # devuelvan arrays/hashes en lugar de strings
  serialize :data, JSON
  serialize :row_errors, JSON
end
