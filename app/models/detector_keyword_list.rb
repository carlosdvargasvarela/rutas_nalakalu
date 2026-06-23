class DetectorKeywordList < ApplicationRecord
  serialize :values_list, coder: JSON

  validates :detector, presence: true
  validates :list_name, presence: true, uniqueness: {scope: :detector}
end
