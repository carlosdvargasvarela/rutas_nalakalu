class AppSetting < ApplicationRecord
  has_paper_trail

  validates :key, presence: true, uniqueness: true

  def self.get(key, default: nil)
    find_by(key: key)&.value.presence || default
  end

  def self.set(key, value)
    find_or_initialize_by(key: key).tap { |s| s.update!(value: value.to_s) }
  end
end
