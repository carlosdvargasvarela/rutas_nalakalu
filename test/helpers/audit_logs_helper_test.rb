require "test_helper"

class AuditLogsHelperTest < ActionView::TestCase
  include AuditLogsHelper

  test "format_change_value translates DeliveryPlan.status" do
    assert_equal "En progreso", format_change_value(3, "status", "DeliveryPlan")
  end

  test "format_change_value translates DeliveryPlan.load_status" do
    assert_equal "Con faltantes", format_change_value(3, "load_status", "DeliveryPlan")
  end

  test "format_change_value translates DeliveryPlanAssignment.status" do
    assert_equal "En ruta", format_change_value(1, "status", "DeliveryPlanAssignment")
  end
end
