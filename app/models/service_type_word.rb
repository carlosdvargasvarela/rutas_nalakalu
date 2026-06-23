class ServiceTypeWord < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :label, presence: true
end
