require "test_helper"

class Production::LoadingFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TS = {"Accept" => "text/vnd.turbo-stream.html"}.freeze

  setup do
    @plan = delivery_plans(:one)
    @delivery = deliveries(:one)
    @delivery.update!(delivery_date: Date.current)
    @item = @delivery.delivery_items.first
    @item.update_columns(status: DeliveryItem.statuses[:pending], load_status: 0)
    @plan.delivery_plan_assignments.find_or_create_by!(delivery: @delivery)
    @user = users(:one)
    @user.update!(role: :logistics, email: "logistica@test.com", password: "password123", password_confirmation: "password123")
    sign_in @user
  end

  test "index lista los planes del día" do
    get production_delivery_plans_path(date: Date.current)
    assert_response :success
  end

  test "loading renderiza el plan con filtros" do
    get loading_production_delivery_plan_path(@plan)
    assert_response :success
    get loading_production_delivery_plan_path(@plan, load_status: "empty")
    assert_response :success
  end

  test "mark_loaded / missing / unloaded por turbo_stream" do
    post mark_loaded_production_delivery_item_path(@item), headers: TS
    assert_response :success
    assert_equal "loaded", @item.reload.load_status
    post mark_missing_production_delivery_item_path(@item), headers: TS
    assert_response :success
    assert_equal "missing", @item.reload.load_status
    post mark_unloaded_production_delivery_item_path(@item), headers: TS
    assert_response :success
    assert_equal "unloaded", @item.reload.load_status
  end

  test "mark_all_loaded del plan y de la entrega" do
    post mark_all_loaded_production_delivery_plan_path(@plan)
    assert_response :redirect
    assert_equal "loaded", @item.reload.load_status
    assert_not @plan.reload.status_completed?, "cargar el camión no debe completar el plan (ruta)"
    post mark_all_loaded_production_delivery_path(@delivery)
    assert_response :redirect
    post reset_load_status_production_delivery_path(@delivery)
    assert_response :redirect
  end

  test "cambiar el estado de carga por GET no existe (Turbo prefetch lo disparaba al pasar el dedo/mouse)" do
    get "/production/delivery_items/#{@item.id}/mark_loaded"
    assert_response :not_found
    assert_equal "unloaded", @item.reload.load_status
  end

  test "un item entregado no muestra botones de carga" do
    @item.update_columns(status: DeliveryItem.statuses[:delivered])
    get loading_production_delivery_plan_path(@plan)
    assert_response :success
    assert_select "form[action$='/delivery_items/#{@item.id}/mark_loaded']", 0
  end

  test "faltante guarda el motivo y avisa a logística/admin" do
    admin = users(:two)
    admin.update_columns(role: User.roles[:admin])
    assert_difference -> { Notification.count } do
      post mark_missing_production_delivery_item_path(@item, reason: "damaged"), headers: TS
    end
    assert_equal "damaged", @item.reload.missing_reason
    post mark_loaded_production_delivery_item_path(@item), headers: TS
    assert_nil @item.reload.missing_reason
  end

  test "las paradas se listan en orden de carga (la última primero)" do
    orders = @plan.loading_assignments.map(&:stop_order)
    assert_equal orders.sort.reverse, orders
  end

  test "cerrar la carga la bloquea, registra el evento y solo un jefe la reabre" do
    post close_load_production_delivery_plan_path(@plan)
    assert @plan.reload.load_closed?
    assert_equal "load_closed", @plan.plan_events.last.action

    post mark_loaded_production_delivery_item_path(@item), headers: TS
    assert_equal "unloaded", @item.reload.load_status

    post reopen_load_production_delivery_plan_path(@plan)
    assert @plan.reload.load_closed?, "logística no puede reabrir"
    @user.update!(role: :admin)
    post reopen_load_production_delivery_plan_path(@plan)
    assert_not @plan.reload.load_closed?
  end

  test "checklist imprimible" do
    get checklist_production_delivery_plan_path(@plan)
    assert_response :success
  end
end
