# app/models/delivery_plan_location.rb
class DeliveryPlanLocation < ApplicationRecord
  belongs_to :delivery_plan

  validates :latitude, :longitude, :captured_at, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :source, inclusion: { in: %w[live batch] }

  scope :ordered, -> { order(captured_at: :asc) }
  scope :recent, ->(limit = 100) { order(captured_at: :desc).limit(limit) }
  scope :for_plan, ->(plan_id) { where(delivery_plan_id: plan_id) }
  scope :between, ->(start_time, end_time) { where(captured_at: start_time..end_time) }

  def self.create_from_batch(delivery_plan, positions_array)
    records = positions_array.map do |pos|
      {
        delivery_plan_id: delivery_plan.id,
        latitude: pos[:lat],
        longitude: pos[:lng],
        speed: pos[:speed],
        heading: pos[:heading],
        accuracy: pos[:accuracy],
        captured_at: pos[:at] || Time.current,
        source: "batch",
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    insert_all(records) if records.any?
  end
end
