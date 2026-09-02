require "test_helper"

module Api
  module V1
    module Driver
      class DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
        setup do
          @driver = users(:one)
          @plan   = delivery_plans(:plan_for_driver)
        end

        def auth
          {"X-Driver-Token" => "test_driver_token_abc123"}
        end

        test "index devuelve array JSON" do
          get api_v1_driver_delivery_plans_path, headers: auth
          assert_response :success
          assert JSON.parse(response.body).is_a?(Array)
        end

        test "index requiere token" do
          get api_v1_driver_delivery_plans_path
          assert_response :unauthorized
        end

        test "index devuelve planes de cualquier conductor, no solo del autenticado" do
          other_plan = delivery_plans(:one) # sin driver asignado
          get api_v1_driver_delivery_plans_path, headers: auth
          ids = JSON.parse(response.body).map { |p| p["id"] }
          assert_includes ids, @plan.id
          assert_includes ids, other_plan.id
        end

        test "show devuelve plan con assignments y progress" do
          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success
          json = JSON.parse(response.body)
          assert json.key?("assignments")
          assert json.key?("progress")
          assert json.key?("status")
        end

        test "show funciona para un plan sin conductor asignado" do
          other = delivery_plans(:one)
          get api_v1_driver_delivery_plan_path(other), headers: auth
          assert_response :success
        end

        test "show funciona para un plan asignado a OTRO conductor" do
          other_driver_auth = {"X-Driver-Token" => "test_driver_token_def456"}
          get api_v1_driver_delivery_plan_path(@plan), headers: other_driver_auth
          assert_response :success
        end

        test "start transiciona a in_progress" do
          @plan.update!(status: :routes_created)
          patch start_api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success
          assert_equal "in_progress", @plan.reload.status
        end

        test "abort transiciona a aborted" do
          @plan.update!(status: :in_progress)
          patch abort_api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success
          assert_equal "aborted", @plan.reload.status
        end

        test "update_position_batch guarda posiciones y actualiza current_lat/lng" do
          positions = [
            {latitude: 9.9341, longitude: -84.0875, accuracy: 5.0, timestamp: Time.current.iso8601}
          ]
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan),
               params: {positions: positions},
               headers: auth
          assert_response :success
          json = JSON.parse(response.body)
          assert_equal 1, json["saved"]
          @plan.reload
          assert_in_delta 9.9341, @plan.current_lat, 0.001
        end
      end
    end
  end
end
