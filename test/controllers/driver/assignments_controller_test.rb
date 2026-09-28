require "test_helper"

module Driver
  class AssignmentsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @driver = User.create!(name: "Chofer Test", email: "chofer_pwa@test.com", role: :driver,
        password: "Nalakalu.01", force_password_change: false)
      @assignment = delivery_plan_assignments(:assignment_for_driver)
      @assignment.update!(status: :pending)
    end

    test "start marca el assignment como in_route" do
      sign_in @driver
      patch start_driver_assignment_path(@assignment)

      assert_response :success
      json = JSON.parse(response.body)
      assert json["success"]
      assert_equal "in_route", json["assignment"]["status"]
      assert_equal "in_route", @assignment.reload.status
    end

    test "start es idempotente si ya está in_route" do
      @assignment.update!(status: :in_route, started_at: 1.hour.ago)
      sign_in @driver
      patch start_driver_assignment_path(@assignment)

      assert_response :success
      assert JSON.parse(response.body)["success"]
    end

    test "un usuario que no es conductor no puede iniciar la parada" do
      seller = User.create!(name: "Vendedor Test", email: "vendedor_pwa@test.com", role: :seller,
        password: "Nalakalu.01", force_password_change: false, seller_code: "V1")
      sign_in seller
      patch start_driver_assignment_path(@assignment)

      assert_redirected_to root_path
      assert_equal "pending", @assignment.reload.status
    end

    test "start también inicia las paradas pendientes del mismo lugar (mismo stop_order)" do
      sibling = same_stop_sibling_for(@assignment)
      sign_in @driver

      patch start_driver_assignment_path(@assignment)

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal [{"id" => sibling.id}], json["group_siblings"]
      assert_equal "in_route", sibling.reload.status
    end

    test "complete reporta las otras paradas activas del mismo lugar sin tocarlas" do
      sibling = same_stop_sibling_for(@assignment)
      @assignment.update!(status: :in_route)
      sign_in @driver

      patch complete_driver_assignment_path(@assignment)

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal [sibling.id], json["group_siblings"].map { |s| s["id"] }
      assert_equal "pending", sibling.reload.status
    end

    private

    def same_stop_sibling_for(assignment)
      other_delivery = Delivery.create!(
        order: orders(:two),
        delivery_address: assignment.delivery.delivery_address,
        delivery_date: assignment.delivery.delivery_date,
        status: :in_plan
      )
      sibling = assignment.delivery_plan.delivery_plan_assignments.create!(delivery: other_delivery, status: :pending)
      # acts_as_list reordena al crear; forzamos el mismo stop_order que el
      # original con update_column, igual que hace DeliveryPlanStopGrouper.
      sibling.update_column(:stop_order, assignment.stop_order)
      sibling
    end
  end
end
