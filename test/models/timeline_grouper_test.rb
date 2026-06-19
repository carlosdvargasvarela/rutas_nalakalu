require "test_helper"

class TimelineGrouperTest < ActiveSupport::TestCase
  FakeRecord = Struct.new(:actor_id, :whodunnit)

  test "groups a plan_event with a paper_trail entry from the same actor within the window" do
    now = Time.current
    plan_entry = TimelineEntry.new(timestamp: now, source: :plan_event, record: FakeRecord.new(7, nil))
    pt_entry = TimelineEntry.new(timestamp: now - 10.seconds, source: :paper_trail, record: FakeRecord.new(nil, "7"))

    groups = TimelineGrouper.group([plan_entry, pt_entry])

    assert_equal 1, groups.size
    assert_equal plan_entry, groups.first[:primary]
    assert_equal [pt_entry], groups.first[:secondary]
  end

  test "does not group entries from different actors even within the window" do
    now = Time.current
    plan_entry = TimelineEntry.new(timestamp: now, source: :plan_event, record: FakeRecord.new(7, nil))
    pt_entry = TimelineEntry.new(timestamp: now - 10.seconds, source: :paper_trail, record: FakeRecord.new(nil, "9"))

    groups = TimelineGrouper.group([plan_entry, pt_entry])

    assert_equal 2, groups.size
  end

  test "plan_event? is true only for entries sourced from :plan_event" do
    entry = TimelineEntry.new(timestamp: Time.current, source: :plan_event, record: FakeRecord.new(1, nil))

    assert entry.plan_event?
    refute entry.delivery_event?
    refute entry.paper_trail?
  end
end
