class DeliveryImport < ApplicationRecord
  belongs_to :user
  has_one_attached :file
  has_many :delivery_import_rows, dependent: :destroy

  enum :status, { pending: 0, processing: 1, ready_for_review: 2, importing: 3, finished: 4, failed: 5 }
end