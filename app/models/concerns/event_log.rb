module EventLog
  extend ActiveSupport::Concern

  included do
    validates :action, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :for_action, ->(action) { where(action: action) }
    scope :by_actor, ->(user_id) { where(actor_id: user_id) }
  end

  def payload_data
    return {} if payload.blank?
    JSON.parse(payload)
  rescue JSON::ParserError => e
    Rails.logger.error("#{self.class}#payload_data error: #{e.message}")
    {}
  end

  def label
    self.class::ACTION_LABELS[action] || action.humanize
  end

  def color
    self.class::ACTION_COLORS[action] || "secondary"
  end

  def icon
    self.class::ACTION_ICONS[action] || "bi-circle"
  end

  def actor_name
    actor&.name || "Sistema"
  end

  class_methods do
    def record_event(attrs)
      create!(attrs.merge(created_at: Time.current))
    rescue => e
      Rails.logger.error("❌ #{name}.record_event falló [#{attrs[:action]}]: #{e.message}")
      nil
    end
  end
end
