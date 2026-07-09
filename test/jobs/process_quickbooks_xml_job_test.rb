require "test_helper"
require "minitest/mock"

class ProcessQuickbooksXmlJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def so_with_duplicate_lines(ref_number)
    {
      "txn_id" => "txn-#{ref_number}",
      "ref_number" => ref_number,
      "time_modified" => Time.current.iso8601,
      "due_date" => Date.tomorrow.to_s,
      "sales_rep_ref" => {"full_name" => sellers(:one).seller_code},
      "customer_ref" => {"full_name" => "Cliente QB"},
      "sales_order_line_ret" => [
        {"txn_line_id" => "L1", "quantity" => "3", "desc" => "Silla Roja"},
        {"txn_line_id" => "L2", "quantity" => "7", "desc" => "Silla Roja"}
      ]
    }
  end

  test "two lines with the same product on a new order are summed into a single order_item" do
    ProcessQuickbooksXmlJob.new.perform([so_with_duplicate_lines("3001")])

    order = Order.find_by(number: "PED-3001")
    items = order.order_items.where(product: "Silla Roja")

    assert_equal 1, items.count, "duplicate product lines must merge into one order_item"
    assert_equal 10, items.first.quantity
  end

  test "two lines with the same product on an existing order are summed instead of overwritten" do
    order = orders(:one)
    order.update!(number: "PED-2001", qb_txn_id: "existing-txn", qb_updated_at: 1.day.ago)

    ProcessQuickbooksXmlJob.new.perform([so_with_duplicate_lines("2001").merge("txn_id" => "existing-txn")])

    items = order.order_items.where(product: "Silla Roja")
    assert_equal 1, items.count, "duplicate product lines must merge into one order_item"
    assert_equal 10, items.first.quantity
  end

  test "a line with blank quantity loads with quantity 1 instead of bouncing the order" do
    so = so_with_duplicate_lines("4001")
    so["sales_order_line_ret"] = [{"txn_line_id" => "L1", "quantity" => "", "desc" => "Silla Azul"}]

    ProcessQuickbooksXmlJob.new.perform([so])

    order = Order.find_by(number: "PED-4001")
    assert order.present?, "order with a blank-quantity line must still be created"
    assert_equal 1, order.order_items.find_by(product: "Silla Azul").quantity
  end

  test "a rejected order emails admins with notifications enabled" do
    admin = users(:one)
    admin.update!(role: :admin, send_notifications: true)

    so = so_with_duplicate_lines("5001")
    so["sales_rep_ref"] = {"full_name" => "NO-SUCH-SELLER"}

    mailer_stub = Object.new
    def mailer_stub.admin_orders_rejected = self
    def mailer_stub.deliver_later = true

    captured_params = nil
    QuickbooksImportMailer.stub :with, ->(params) { captured_params = params; mailer_stub } do
      ProcessQuickbooksXmlJob.new.perform([so])
    end

    assert_equal admin, captured_params[:admin]
    assert_equal "5001", captured_params[:rejected].first[:order_number]
    assert_match "NO-SUCH-SELLER", captured_params[:rejected].first[:reason]
    assert_nil Order.find_by(number: "PED-5001"), "order with an unknown seller must not be created"
  end
end
