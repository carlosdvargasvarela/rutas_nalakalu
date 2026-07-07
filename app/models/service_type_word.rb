class ServiceTypeWord < ApplicationRecord
  has_paper_trail

  validates :key, presence: true, uniqueness: true
  validates :label, presence: true
end
