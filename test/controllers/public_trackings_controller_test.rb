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

  test "json poll endpoint returns the truck position while in_route" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:in_route])
    plan = assignment.delivery_plan
    plan.update_columns(current_lat: 9.93, current_lng: -84.08, last_seen_at: Time.current)
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token, format: :json)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 9.93, body["current_lat"]
    assert_equal(-84.08, body["current_lng"])
    assert body["last_seen_at"].present?
    assert_equal "live", body["stage"]
  end

  test "json poll endpoint exposes nothing outside the live stage" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending])
    delivery = assignment.delivery

    get public_tracking_url(token: delivery.tracking_token, format: :json)

    assert_response :success
    assert_equal({"stage" => "waiting"}, JSON.parse(response.body))
  end

  test "waiting stage shows client name, delay note and ETA with assembly buffer, no address of other stops" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending], stop_order: 1)
    plan = assignment.delivery_plan
    addr = assignment.delivery.delivery_address
    addr.update_columns(latitude: 9.93, longitude: -84.08)
    plan.update_columns(current_lat: 9.93, current_lng: -84.08, last_seen_at: Time.current)

    get public_tracking_url(token: assignment.delivery.tracking_token)

    assert_response :success
    assert_match assignment.delivery.order.client.name, response.body
    assert_match "presas", response.body
    assert_select "strong", text: /5 minutos/

    # buffer de una parada anterior con producto "armado"
    assignment.update_columns(stop_order: 2)
    other = plan.delivery_plan_assignments.where.not(id: assignment.id).first
    if other
      other.update_columns(stop_order: 1, status: DeliveryPlanAssignment.statuses[:pending])
      other.delivery.delivery_address.update_columns(latitude: 9.93, longitude: -84.08)
      other.delivery.delivery_items.first.order_item.update_columns(product: "Cama con armado")
      DetectorKeywordList.create!(detector: "assembly_buffer", list_name: "minutes", values_list: ["armado=30"])
      get public_tracking_url(token: assignment.delivery.tracking_token)
      assert_select "strong", text: /(4[05]) minutos/
    end
  end

  test "WaitingEta.humanize switches to hours from 60 minutes" do
    assert_equal "45 minutos", Deliveries::WaitingEta.humanize(45)
    assert_equal "1 hora", Deliveries::WaitingEta.humanize(60)
    assert_equal "1 hora y 30 minutos", Deliveries::WaitingEta.humanize(90)
    assert_equal "2 horas", Deliveries::WaitingEta.humanize(120)
  end

  test "waiting stage lists every order of the same client in the same stop" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending], stop_order: 1)
    other = deliveries(:two)
    assert_not_equal assignment.delivery.order_id, other.order_id
    other.order.update_columns(client_id: assignment.delivery.order.client_id, number: "OTRO-1")
    DeliveryPlanAssignment.create!(delivery: other, delivery_plan: assignment.delivery_plan).update_columns(stop_order: 1)

    get public_tracking_url(token: assignment.delivery.tracking_token)

    assert_response :success
    assert_match "Pedidos", response.body
    assert_match "##{other.order.number}", response.body
  end

  test "a sibling order in route puts every order of the stop on the live stage" do
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending], stop_order: 1)
    other = deliveries(:two)
    other.order.update_columns(client_id: assignment.delivery.order.client_id, number: "OTRO-1")
    sibling = DeliveryPlanAssignment.create!(delivery: other, delivery_plan: assignment.delivery_plan)
    sibling.update_columns(stop_order: 1, status: DeliveryPlanAssignment.statuses[:in_route])

    get public_tracking_url(token: assignment.delivery.tracking_token)

    assert_match "public-tracking-map", response.body
  end

  test "WaitingEta usa velocidad de carretera en tramos largos" do
    tramo = ->(a, b) { Deliveries::WaitingEta.send(:travel_minutes, a, b) }
    # Palmares -> Tamarindo (~150 km en línea recta): horas, no medio día
    assert_in_delta 3.5 * 60, tramo.([9.94, -84.44], [10.30, -85.84]), 45
    # tramo urbano de ~2 km en línea recta: unos minutos
    assert_operator tramo.([9.93, -84.08], [9.945, -84.08]), :<, 10
  end
end
