require "test_helper"
require "minitest/mock"

class DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "update_order guarda exactamente el stop_order pedido, incluso con paradas agrupadas por misma ubicación" do
    plan = delivery_plans(:one)
    plan.delivery_plan_assignments.destroy_all

    d1 = deliveries(:one)
    others = 3.times.map do |i|
      d = d1.dup
      d.tracking_token = "regress_stop_order_#{i}"
      d.save!
      d
    end

    a1 = DeliveryPlanAssignment.create!(delivery_plan: plan, delivery: d1)
    a2 = DeliveryPlanAssignment.create!(delivery_plan: plan, delivery: others[0])
    # a3 comparte ubicación con a2 (mismo stop_order), como agrupa
    # DeliveryPlanStopGrouper para paradas físicamente cercanas.
    a3 = DeliveryPlanAssignment.create!(delivery_plan: plan, delivery: others[1])
    a3.update_column(:stop_order, a2.stop_order)
    a4 = DeliveryPlanAssignment.create!(delivery_plan: plan, delivery: others[2])

    new_positions = {a4.id => 1, a1.id => 2, a2.id => 3, a3.id => 3}

    # Aislamos el compactado posterior (DeliveryPlanStopGrouper) para poder
    # verificar los valores crudos que el propio loop de update_order
    # persiste. acts_as_list interceptaba cada update!(stop_order: ...) como
    # un insert_at() y desplazaba en cascada las paradas vecinas ya
    # reordenadas por este mismo loop, sobre todo con stop_order repetidos.
    noop_grouper = Class.new { def initialize(*); end; def call; end }
    DeliveryPlanStopGrouper.stub :new, ->(plan) { noop_grouper.new(plan) } do
      patch update_order_delivery_plan_url(plan), params: {stop_orders: new_positions}, as: :json
    end

    assert_response :success
    assert_equal(
      new_positions,
      DeliveryPlanAssignment.where(id: new_positions.keys).index_by(&:id).transform_values(&:stop_order)
    )
  end

  test "should get new" do
    get new_delivery_plan_url
    assert_response :success
  end

  test "index xlsx no truena cuando un plan tiene entregas con estado oculto" do
    # Regresión: el auto_filter se calculaba sobre TODAS las asignaciones del
    # plan, pero las filas solo se escriben para las visibles (VISIBLE_TO_ALL_
    # STATUSES) — con una entrega cancelada/reagendada de más, el rango del
    # auto_filter apuntaba a celdas que nunca existieron y Axlsx tronaba con
    # "undefined method 'pos' for nil" al serializar el .xlsx.
    deliveries(:two).update!(status: :cancelled)

    get delivery_plans_url(format: :xlsx)

    assert_response :success
  end

  test "should get create" do
    post delivery_plans_url, params: {
      delivery_plan: {status: :draft},
      delivery_ids: [deliveries(:one).id]
    }
    assert_redirected_to edit_delivery_plan_path(DeliveryPlan.last)
  end

  test "send_to_logistics rechaza un plan sin paradas" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft], driver_id: users(:one).id)
    plan.delivery_plan_assignments.destroy_all

    patch send_to_logistics_delivery_plan_url(plan)

    assert_redirected_to edit_delivery_plan_path(plan)
    assert_equal "draft", plan.reload.status
    follow_redirect!
    assert_match "al menos una parada", response.body
  end

  test "send_to_logistics funciona con conductor y al menos una parada" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft], driver_id: users(:one).id)

    patch send_to_logistics_delivery_plan_url(plan)

    assert_redirected_to delivery_plan_path(plan)
    assert_equal "routes_created", plan.reload.status
  end

  test "show hides a cancelled delivery from a non-admin but keeps it visible for admin" do
    plan = delivery_plans(:one)
    delivery = delivery_plan_assignments(:one).delivery
    delivery.update_columns(status: Delivery.statuses[:cancelled])
    delivery_marker = "productosEntrega#{delivery.id}"

    sign_out @admin
    seller = users(:two)
    seller.update!(role: :seller, force_password_change: false)
    sign_in seller

    get delivery_plan_url(plan)
    assert_response :success
    refute_match delivery_marker, response.body

    sign_out seller
    sign_in @admin

    get delivery_plan_url(plan)
    assert_response :success
    assert_match delivery_marker, response.body
    assert_match "Cancelad", response.body
  end

  test "show hides a cancelled product from a non-admin but keeps it visible (flagged) for admin" do
    plan = delivery_plans(:one)
    item = delivery_plan_assignments(:one).delivery.delivery_items.first
    item.update_columns(status: DeliveryItem.statuses[:cancelled])
    item.order_item.update_columns(product: "PRODUCTO-UNICO-TEST-123")

    get delivery_plan_url(plan)
    assert_response :success
    assert_match "PRODUCTO-UNICO-TEST-123", response.body
    assert_match "Cancelad", response.body
  end

  test "show muestra ETA solo en paradas pendientes o en ruta con GPS reciente" do
    plan = delivery_plans(:one)
    assignment = delivery_plan_assignments(:one)
    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending], stop_order: 1)
    assignment.delivery.delivery_address.update_columns(latitude: 9.93, longitude: -84.08)
    plan.update_columns(current_lat: 9.93, current_lng: -84.08, last_seen_at: Time.current)

    get delivery_plan_url(plan)
    assert_response :success
    assert_match "en ~5 minutos", response.body

    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:completed])
    get delivery_plan_url(plan)
    refute_match "en ~5 minutos", response.body

    assignment.update_columns(status: DeliveryPlanAssignment.statuses[:pending])
    assignment.delivery.update_columns(status: Delivery.statuses[:rescheduled])
    get delivery_plan_url(plan)
    refute_match "en ~5 minutos", response.body
  end
end
