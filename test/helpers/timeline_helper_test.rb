require "test_helper"

class TimelineHelperTest < ActionView::TestCase
  include AuditLogsHelper
  include DeliveryEventsHelper
  include PlanEventsHelper
  include TimelineHelper

  test "timeline_description shows the deleted record's fields for a destroy version, not 'Sin cambios detectados'" do
    item = delivery_items(:one)
    item.update!(status: :delivered)
    item.destroy!

    version = PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id, event: "destroy").last
    entry = TimelineEntry.new(timestamp: version.created_at, source: :paper_trail, record: version)

    refute_equal "Sin cambios detectados", timeline_description(entry)
  end

  test "timeline_description shows the created record's fields for a create version" do
    delivery = deliveries(:one)
    item = delivery.delivery_items.create!(order_item: order_items(:two), quantity_delivered: 2, status: :confirmed)

    version = PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id, event: "create").last
    entry = TimelineEntry.new(timestamp: version.created_at, source: :paper_trail, record: version)

    assert_match(/Confirmado/, timeline_description(entry))
  end

  test "timeline_icon/color/title delegate to the record for plan_event entries" do
    plan = DeliveryPlan.create!(week: "50", year: 2026, status: :draft)
    event = plan.plan_events.last # "created", generado por el callback de Task 6

    entry = TimelineEntry.new(timestamp: event.created_at, source: :plan_event, record: event)

    assert_equal event.icon, timeline_icon(entry)
    assert_equal event.color, timeline_color(entry)
    assert_equal event.label, timeline_title(entry)
    assert_equal "Sistema", timeline_actor(entry)
  end
end
