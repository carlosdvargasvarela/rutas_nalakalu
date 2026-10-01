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
    assert_nil Order.find_by(number: "PED-5001", qb_standby: false), "order with an unknown seller must not be operational"
  end

  test "same order number with a different QB txn goes to stand-by and never overwrites" do
    order = orders(:one)
    order.update!(number: "PED-2002", qb_txn_id: "txn-A", qb_updated_at: 1.day.ago)
    items_before = order.order_items.pluck(:product, :quantity).sort

    ProcessQuickbooksXmlJob.new.perform([so_with_duplicate_lines("2002").merge("txn_id" => "txn-B")])

    assert_equal items_before, order.reload.order_items.pluck(:product, :quantity).sort
    assert_equal "txn-A", order.qb_txn_id
    held = Order.find_by!(number: "PED-2002", qb_standby: true)
    assert_equal "txn-B", held.qb_txn_id
    assert_equal 10, held.order_items.find_by(product: "Silla Roja").quantity
    assert held.deliveries.all?(&:pending_review?), "stand-by deliveries must not be operational"

    # reenvío de la misma transacción: no duplica ni toca nada
    assert_no_difference -> { Order.count } do
      ProcessQuickbooksXmlJob.new.perform([so_with_duplicate_lines("2002").merge("txn_id" => "txn-B")])
    end
  end

  test "new order without address or products is saved as stand-by, not as a usable order" do
    so = so_with_duplicate_lines("2003").merge("sales_order_line_ret" => nil, "customer_ref" => {"full_name" => "Otro Cliente"})

    ProcessQuickbooksXmlJob.new.perform([so])

    assert_nil Order.find_by(number: "PED-2003", qb_standby: false)
    held = Order.find_by!(number: "PED-2003", qb_standby: true)
    assert_match(/sin dirección/, held.qb_standby_reason)
    assert_match(/sin productos/, held.qb_standby_reason)
    assert held.deliveries.all?(&:pending_review?)
    assert_equal 0, QbStandbyOrder.count
  end

  def so_with_contacts(ref, ext_phone, addr_phone)
    so_with_duplicate_lines(ref).merge(
      "data_ext_ret" => [{"data_ext_name" => "Contacto de Entrega", "data_ext_value" => "Armando Jose"},
        {"data_ext_name" => "Celular de Contacto Entrega", "data_ext_value" => ext_phone}],
      "ship_address" => {"addr1" => "Condominio Santa Ana", "addr2" => "Contacto: Armando Jose", "city" => "Telefono:+506#{addr_phone}"}
    )
  end

  test "a different contact in the address block is added as an extra order contact" do
    ProcessQuickbooksXmlJob.new.perform([so_with_contacts("3002", "88449617", "85188679")])

    contacts = Order.find_by!(number: "PED-3002").order_contacts.order(:id).pluck(:name, :phone, :is_primary)
    assert_equal [["Armando Jose", "88449617", true], ["Armando Jose", "85188679", false]], contacts
  end

  test "the same contact in the address block is not duplicated" do
    ProcessQuickbooksXmlJob.new.perform([so_with_contacts("3003", "88449617", "88449617")])

    assert_equal 1, Order.find_by!(number: "PED-3003").order_contacts.count
  end
end
