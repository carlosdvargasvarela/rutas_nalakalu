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
  end
end
