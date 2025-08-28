class DeliveryImportRow < ApplicationRecord
  belongs_to :delivery_import

  attribute :data, :json, default: {}
  attribute :row_errors, :json, default: []
end
