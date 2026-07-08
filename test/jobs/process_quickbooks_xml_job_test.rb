require "test_helper"

class ProcessQuickbooksXmlJobTest < ActiveSupport::TestCase
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
end
