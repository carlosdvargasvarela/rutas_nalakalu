require "test_helper"

class PublicTrackingsControllerTest < ActionDispatch::IntegrationTest
  test "no plan yet renders the no_plan view" do
    delivery_plan_assignments(:one).destroy
    delivery = deliveries(:one)

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :not_found
    assert_select "h3", text: /en proceso/
  end

  test "assignment pending shows the waiting stage without exposing truck position" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending])
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :success
    assert_select "h3", text: /confirmado/
    refute_match "public-tracking-map", response.body
  end

  test "assignment in_route shows the live map stage" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:in_route])
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :success
    assert_match "public-tracking-map", response.body
    refute_match "public-tracking-waiting", response.body
  end

  test "assignment completed shows the delivered stage" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:completed])
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :success
    assert_select "h3", text: /entregado/
  end

  test "assignment cancelled shows the issue stage" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:cancelled])
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :success
    assert_select "h3", text: /problema/
  end

  test "rescheduled delivery shows the issue stage even if the assignment is still pending" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending])
    delivery = assignment.delivery
    delivery.update_columns(status: Delivery.statuses[:rescheduled])

    get public_tracking_url(token: delivery.tracking_token)

    assert_response :success
    assert_select "h3", text: /reagendada/
  end
end
