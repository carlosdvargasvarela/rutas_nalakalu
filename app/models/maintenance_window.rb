# app/models/maintenance_window.rb
class MaintenanceWindow < ApplicationRecord
  has_paper_trail

  belongs_to :activated_by, class_name: "User"

  serialize :allowed_user_ids, coder: JSON

  validates :message, presence: true

  scope :active_windows, -> { where(active: true).order(created_at: :desc) }

  def self.active?
    window = active_windows.first
    return false unless window

    if window.ends_at.present? && window.ends_at < Time.current
      window.update_columns(active: false)
      return false
    end

    true
  end

  def self.current_window
    active_windows.first
  end

  def allows_user?(user)
    return false if user.blank?

    allowed_user_ids.map(&:to_i).include?(user.id)
  end

  def time_remaining
    return nil unless ends_at.present?

    remaining = ((ends_at - Time.current) / 60).ceil
    remaining.positive? ? remaining : 0
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[active ends_at created_at]
  end
end
