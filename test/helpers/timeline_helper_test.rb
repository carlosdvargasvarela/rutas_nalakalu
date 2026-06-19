require "test_helper"

class TimelineHelperTest < ActionView::TestCase
  include AuditLogsHelper
  include DeliveryEventsHelper
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
end
