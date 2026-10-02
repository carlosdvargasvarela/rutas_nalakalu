require "test_helper"

class Admin::QuickbooksStandbyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    ProcessQuickbooksXmlJob.new.perform([{
      "txn_id" => "txn-S", "ref_number" => "5001", "time_modified" => Time.current.iso8601,
      "due_date" => Date.tomorrow.to_s, "sales_rep_ref" => {"full_name" => sellers(:one).seller_code},
      "customer_ref" => {"full_name" => "Cliente S"},
      "sales_order_line_ret" => [{"txn_line_id" => "S1", "quantity" => "2", "desc" => "Mesa"}]
    }])
    @order = Order.find_by!(number: "PED-5001", qb_standby: true)
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin
  end

  test "edit address and products of a stand-by order, then release" do
    get admin_quickbooks_path
    assert_response :success
    get orders_path(q: {number_cont: "5001"})
    assert_response :success
    assert_no_match(/PED-5001/, response.body, "stand-by orders must not be listed")
    get deliveries_path
    assert_no_match(/PED-5001/, response.body, "pending-review deliveries are hidden from the default index")
    get deliveries_path(q: {status_in: ["pending_review"]})
    assert_match(/PED-5001/, response.body)
    assert_not_includes Delivery.available_for_plan.pluck(:id), @order.deliveries.first.id
    get admin_edit_standby_quickbooks_path(@order)
    assert_response :success

    item = @order.order_items.first
    patch admin_standby_quickbooks_path(@order), params: {
      address: "San José, Escazú", items: {item.id => {product: "Mesa Roble", quantity: "3"}},
      new_product: "Silla", new_quantity: "4"
    }
    assert_redirected_to admin_quickbooks_path
    assert_equal "San José, Escazú", @order.deliveries.first.delivery_address.address
    assert_equal [["Mesa Roble", 3], ["Silla", 4]], @order.order_items.order(:id).pluck(:product, :quantity)
    assert @order.deliveries.first.reload.pending_review?, "still not operational"

    post admin_release_quickbooks_standby_path(@order), params: {number: "PED-5001"}
    assert_not @order.reload.qb_standby
    assert @order.deliveries.first.scheduled?
  end

  test "a released order renamed on release is not re-held when QB resends it" do
    other = orders(:one)
    other.update!(number: "PED-5001", qb_txn_id: "txn-orig", qb_updated_at: 1.day.ago)
    patch admin_standby_quickbooks_path(@order), params: {address: "Heredia centro"}
    post admin_release_quickbooks_standby_path(@order), params: {number: "PED-5001-B"}
    assert_equal "PED-5001-B", @order.reload.number

    assert_no_difference -> { Order.count + QbStandbyOrder.count } do
      ProcessQuickbooksXmlJob.new.perform([{
        "txn_id" => "txn-S", "ref_number" => "5001", "time_modified" => Time.current.iso8601,
        "due_date" => Date.tomorrow.to_s, "sales_rep_ref" => {"full_name" => sellers(:one).seller_code},
        "customer_ref" => {"full_name" => "Cliente S"},
        "sales_order_line_ret" => [{"txn_line_id" => "S1", "quantity" => "2", "desc" => "Mesa"}]
      }])
    end
  end

  test "unknown seller and client placeholders block release until set; date, client and seller are editable" do
    ProcessQuickbooksXmlJob.new.perform([{
      "txn_id" => "txn-U", "ref_number" => "5002", "time_modified" => Time.current.iso8601,
      "due_date" => Date.tomorrow.to_s, "sales_rep_ref" => {"full_name" => "NO-EXISTE"},
      "sales_order_line_ret" => [{"txn_line_id" => "U1", "quantity" => "1", "desc" => "Sofá"}]
    }])
    order = Order.find_by!(number: "PED-5002", qb_standby: true)
    assert_equal "SIN-ASIGNAR", order.seller.seller_code
    assert_match(/NO-EXISTE/, order.qb_standby_reason)

    post admin_release_quickbooks_standby_path(order)
    assert order.reload.qb_standby, "must not release with placeholders"

    patch admin_standby_quickbooks_path(order), params: {
      client_name: "Cliente Nuevo", seller_id: sellers(:one).id, delivery_date: "2030-01-15", address: "Heredia centro"
    }
    order.reload
    assert_equal "Cliente Nuevo", order.client.name
    assert_equal sellers(:one), order.seller
    assert_equal Date.new(2030, 1, 15), order.deliveries.first.delivery_date.to_date
    assert_equal order.client, order.deliveries.first.delivery_address.client

    post admin_release_quickbooks_standby_path(order)
    assert_not order.reload.qb_standby
  end
end
