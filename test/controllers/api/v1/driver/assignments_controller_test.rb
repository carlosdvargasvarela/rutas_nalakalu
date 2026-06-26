require "test_helper"

module Api
  module V1
    module Driver
      class AssignmentsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @driver     = users(:one)
          @assignment = delivery_plan_assignments(:assignment_for_driver)
        end

        def auth
          {"X-Driver-Token" => "test_driver_token_abc123"}
        end

        test "complete marca el assignment" do
          @assignment.update!(status: :in_route)
          patch complete_api_v1_driver_assignment_path(@assignment), headers: auth
          assert_response :success
          assert JSON.parse(response.body)["success"]
        end

        test "fail marca el assignment como cancelado con razón" do
          @assignment.update!(status: :in_route)
          patch fail_api_v1_driver_assignment_path(@assignment),
                params: {reason: "Cliente no estaba"},
                headers: auth
          assert_response :success
          assert JSON.parse(response.body)["success"]
        end

        test "add_note agrega nota al assignment" do
          patch add_note_api_v1_driver_assignment_path(@assignment),
                params: {note: "Sin elevador"},
                headers: auth
          assert_response :success
          assert @assignment.reload.driver_notes.include?("Sin elevador")
        end

        test "add_note rechaza nota vacía" do
          patch add_note_api_v1_driver_assignment_path(@assignment),
                params: {note: ""},
                headers: auth
          assert_response :unprocessable_entity
        end

        test "rechaza acceso sin token" do
          patch complete_api_v1_driver_assignment_path(@assignment)
          assert_response :unauthorized
        end

        test "rechaza assignment de otro conductor" do
          other = delivery_plan_assignments(:one)
          patch complete_api_v1_driver_assignment_path(other), headers: auth
          assert_response :not_found
        end
      end
    end
  end
end
