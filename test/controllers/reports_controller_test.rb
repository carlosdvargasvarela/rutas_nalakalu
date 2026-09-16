require "test_helper"
require "roo"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  # El xlsx viene como binario en response.body: lo escribimos a un tmpfile
  # y lo leemos con Roo (igual que RouteExcelImportService) para poder
  # aserter sobre el contenido real de las celdas en vez del blob crudo.
  def xlsx_rows
    file = Tempfile.new(["report", ".xlsx"])
    file.binmode
    file.write(response.body)
    file.close
    sheet = Roo::Spreadsheet.open(file.path)
    (1..sheet.last_row).map { |r| sheet.row(r) }
  ensure
    file&.unlink
  end

  test "deliveries_in_plan only includes deliveries assigned to a plan" do
    assigned = delivery_plan_assignments(:one).delivery
    assigned.order.update_columns(number: "PED-ASSIGNED-1")

    unassigned = deliveries(:two)
    unassigned.order.update_columns(number: "PED-UNASSIGNED-1")
    DeliveryPlanAssignment.where(delivery_id: unassigned.id).delete_all

    get report_deliveries_in_plan_url(format: :xlsx)
    assert_response :success

    rows = xlsx_rows.flatten.compact.join(" ")
    assert_match "PED-ASSIGNED-1", rows
    refute_match "PED-UNASSIGNED-1", rows
  end

  test "deliveries_in_plan shows a visible note for rescheduled and cancelled deliveries" do
    delivery = delivery_plan_assignments(:one).delivery
    delivery.update_columns(status: Delivery.statuses[:cancelled], delivery_notes: "Cliente pidió cancelar")

    get report_deliveries_in_plan_url(format: :xlsx)
    assert_response :success

    rows = xlsx_rows.flatten.compact.join(" ")
    assert_match "CANCELADA", rows
    assert_match "Cliente pidió cancelar", rows
  end

  test "deliveries_in_plan respects the q ransack filters used by the deliveries index" do
    assigned = delivery_plan_assignments(:one).delivery

    get report_deliveries_in_plan_url(format: :xlsx, q: {order_number_cont: "NO-SUCH-ORDER-XYZ"})
    assert_response :success

    rows = xlsx_rows.flatten.compact.join(" ")
    refute_match assigned.order.number, rows
  end
end
