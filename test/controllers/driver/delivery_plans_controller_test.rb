require "test_helper"

module Driver
  class DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @driver = User.create!(name: "Chofer Test", email: "chofer_pwa2@test.com", role: :driver,
        password: "Nalakalu.01", force_password_change: false)
      @plan = delivery_plans(:plan_for_driver)
    end

    test "update_position_batch persiste los puntos en la bitácora del plan" do
      sign_in @driver

      assert_difference -> { @plan.delivery_plan_locations.count } => 2 do
        post update_position_batch_driver_delivery_plans_path, params: {
          delivery_plan_id: @plan.id,
          positions: [
            {latitude: 9.93, longitude: -84.08, accuracy: 5, timestamp: 1.minute.ago.iso8601},
            {latitude: 9.94, longitude: -84.09, accuracy: 5, timestamp: Time.current.iso8601}
          ]
        }
      end

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal 2, json["saved"]
      assert_equal 9.94, @plan.reload.current_lat.to_f
    end

    test "show cuenta las paradas en_route por separado de pendientes" do
      assignment = delivery_plan_assignments(:assignment_for_driver)
      assignment.update!(status: :in_route)

      sign_in @driver
      get driver_delivery_plan_path(@plan)

      assert_response :success
      assert_select '[data-driver-plan-target="enRouteCount"]', text: "1"
      assert_select '[data-driver-plan-target="pendingCount"]', text: "0"
    end
  end
end
