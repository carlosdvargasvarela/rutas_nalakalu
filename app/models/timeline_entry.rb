# app/models/timeline_entry.rb
class TimelineEntry
  attr_reader :timestamp, :source, :record

  def initialize(timestamp:, source:, record:)
    @timestamp = timestamp
    @source = source
    @record = record
  end

  def delivery_event? = source == :delivery_event
  def paper_trail? = source == :paper_trail
  def created_at = timestamp
end
