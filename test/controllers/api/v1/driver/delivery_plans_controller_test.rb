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
          other_plan.update!(status: :routes_created)
          get api_v1_driver_delivery_plans_path, headers: auth
          ids = JSON.parse(response.body).map { |p| p["id"] }
          assert_includes ids, @plan.id
          assert_includes ids, other_plan.id
        end

        test "index excluye planes completed, aborted o draft" do
          completed = delivery_plans(:one)
          completed.update_columns(status: DeliveryPlan.statuses[:completed])

          get api_v1_driver_delivery_plans_path, headers: auth
          ids = JSON.parse(response.body).map { |p| p["id"] }
          assert_not_includes ids, completed.id
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

        test "update_position_batch rechaza con 409 si otro conductor está activo" do
          @plan.update_columns(last_recorded_by_id: users(:two).id, last_seen_at: 1.minute.ago)

          positions = [{latitude: 9.9341, longitude: -84.0875, accuracy: 5.0, timestamp: Time.current.iso8601}]
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan),
               params: {positions: positions},
               headers: auth

          assert_response :conflict
          json = JSON.parse(response.body)
          assert_equal "otro_conductor_activo", json["error"]
          assert_equal "User Two", json["active_driver_name"]
        end

        test "update_position_batch acepta si el conductor activo lleva más de 5 minutos sin reportar" do
          @plan.update_columns(last_recorded_by_id: users(:two).id, last_seen_at: 6.minutes.ago)

          positions = [{latitude: 9.9341, longitude: -84.0875, accuracy: 5.0, timestamp: Time.current.iso8601}]
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan),
               params: {positions: positions},
               headers: auth

          assert_response :success
          assert_equal @driver.id, @plan.reload.last_recorded_by_id
        end

        test "update_position_batch acepta si el que manda ya es la fuente activa" do
          @plan.update_columns(last_recorded_by_id: @driver.id, last_seen_at: 1.minute.ago)

          positions = [{latitude: 9.9341, longitude: -84.0875, accuracy: 5.0, timestamp: Time.current.iso8601}]
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan),
               params: {positions: positions},
               headers: auth

          assert_response :success
        end

        test "update_position_batch marca recorded_by_id en la ubicación guardada" do
          positions = [{latitude: 9.9341, longitude: -84.0875, accuracy: 5.0, timestamp: Time.current.iso8601}]
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan),
               params: {positions: positions},
               headers: auth

          assert_response :success
          assert_equal @driver.id, @plan.delivery_plan_locations.last.recorded_by_id
        end

        test "index expone active_tracker cuando otro conductor está activo" do
          @plan.update_columns(last_recorded_by_id: users(:two).id, last_seen_at: 1.minute.ago)

          get api_v1_driver_delivery_plans_path, headers: auth
          json = JSON.parse(response.body).find { |p| p["id"] == @plan.id }

          assert_equal({"name" => "User Two"}, json["active_tracker"])
        end

        test "index no expone active_tracker para el propio usuario activo" do
          @plan.update_columns(last_recorded_by_id: @driver.id, last_seen_at: 1.minute.ago)

          get api_v1_driver_delivery_plans_path, headers: auth
          json = JSON.parse(response.body).find { |p| p["id"] == @plan.id }

          assert_nil json["active_tracker"]
        end

        test "show incluye productos, contactos, condominio/casa, vendedor y tracking_url" do
          seller = Seller.create!(name: "Vendedor Test", seller_code: "V-01", user: @driver)
          client = Client.create!(name: "Cliente Test")
          order = Order.create!(client: client, seller: seller, number: "ORD-TEST-1")
          order.order_contacts.create!(name: "Ana Pérez", phone: "8888-0000", is_primary: true)
          order_item = OrderItem.create!(order: order, product: "Sofá 3 plazas", quantity: 2, notes: "Nota del pedido")
          address = DeliveryAddress.create!(client: client, address: "San José, Costa Rica", latitude: 9.93, longitude: -84.08)
          delivery = Delivery.create!(
            order: order,
            delivery_address: address,
            delivery_date: Date.current,
            condominio_number: "B-12",
            casa_number: "45"
          )
          DeliveryItem.create!(delivery: delivery, order_item: order_item, quantity_delivered: 2, notes: "Cuidado, frágil", status: :pending)
          assignment = @plan.delivery_plan_assignments.create!(delivery: delivery, stop_order: 1)

          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success

          stop = JSON.parse(response.body)["assignments"].find { |x| x["id"] == assignment.id }["delivery"]
          assert_equal "V-01", stop["seller_code"]
          assert_equal "B-12", stop["condominio_number"]
          assert_equal "45", stop["casa_number"]
          assert stop["tracking_url"].present?
          assert_equal [{"name" => "Ana Pérez", "phone" => "8888-0000", "is_primary" => true}], stop["contacts"]
          assert_equal 1, stop["items"].size
          item = stop["items"].first
          assert_equal "Sofá 3 plazas", item["product"]
          assert_equal 2, item["quantity"]
          assert_equal "Cuidado, frágil", item["notes"]
          assert_equal "Nota del pedido", item["order_item_notes"]
        end

        test "show incluye crew del conductor asignado al plan" do
          @plan.driver.crew_members.destroy_all
          @plan.driver.crew_members.create!(name: "Carlos Ayudante", id_number: "1-2222-3333")

          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success

          crew = JSON.parse(response.body)["crew"]
          assert_equal [{"name" => "Carlos Ayudante", "id_number" => "1-2222-3333"}], crew
        end

        test "show devuelve tracking_url nulo en vez de 500 si el delivery no tiene tracking_token" do
          client = Client.create!(name: "Cliente Sin Token")
          seller = Seller.create!(name: "Vendedor Sin Token", seller_code: "V-02", user: @driver)
          order = Order.create!(client: client, seller: seller, number: "ORD-TEST-2")
          address = DeliveryAddress.create!(client: client, address: "Heredia, Costa Rica", latitude: 10.0, longitude: -84.1)
          delivery = Delivery.create!(order: order, delivery_address: address, delivery_date: Date.current)
          delivery.update_column(:tracking_token, nil)
          assignment = @plan.delivery_plan_assignments.create!(delivery: delivery, stop_order: 2)

          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success

          stop = JSON.parse(response.body)["assignments"].find { |x| x["id"] == assignment.id }["delivery"]
          assert_nil stop["tracking_url"]
        end

        test "claim_tracking requiere token" do
          patch claim_tracking_api_v1_driver_delivery_plan_path(@plan)
          assert_response :unauthorized
        end

        test "update_position_batch requiere token" do
          post update_position_batch_api_v1_driver_delivery_plan_path(@plan), params: {positions: []}
          assert_response :unauthorized
        end

        test "show excluye una parada cuyo delivery está cancelado" do
          client = Client.create!(name: "Cliente Cancelado")
          seller = Seller.create!(name: "Vendedor X", seller_code: "V-03", user: @driver)
          order = Order.create!(client: client, seller: seller, number: "ORD-TEST-CANCEL")
          address = DeliveryAddress.create!(client: client, address: "Cartago, Costa Rica", latitude: 9.86, longitude: -83.92)
          delivery = Delivery.create!(order: order, delivery_address: address, delivery_date: Date.current)
          assignment = @plan.delivery_plan_assignments.create!(delivery: delivery, stop_order: 3)
          # change_deliveries_statuses (after_create en el assignment) pisa el status a
          # in_plan — hay que fijar "cancelled" después de crear el assignment.
          delivery.update_columns(status: Delivery.statuses[:cancelled])

          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success

          assignment_ids = JSON.parse(response.body)["assignments"].map { |x| x["id"] }
          assert_not_includes assignment_ids, assignment.id
        end

        test "show excluye un producto cancelado pero mantiene los demás de la misma entrega" do
          client = Client.create!(name: "Cliente Producto Cancelado")
          seller = Seller.create!(name: "Vendedor Y", seller_code: "V-04", user: @driver)
          order = Order.create!(client: client, seller: seller, number: "ORD-TEST-ITEM-CANCEL")
          address = DeliveryAddress.create!(client: client, address: "Alajuela, Costa Rica", latitude: 10.02, longitude: -84.21)
          delivery = Delivery.create!(order: order, delivery_address: address, delivery_date: Date.current)
          active_order_item = OrderItem.create!(order: order, product: "Mesa", quantity: 1)
          cancelled_order_item = OrderItem.create!(order: order, product: "Silla cancelada", quantity: 4)
          DeliveryItem.create!(delivery: delivery, order_item: active_order_item, quantity_delivered: 1, status: :pending)
          DeliveryItem.create!(delivery: delivery, order_item: cancelled_order_item, quantity_delivered: 4, status: :cancelled)
          assignment = @plan.delivery_plan_assignments.create!(delivery: delivery, stop_order: 4)

          get api_v1_driver_delivery_plan_path(@plan), headers: auth
          assert_response :success

          stop = JSON.parse(response.body)["assignments"].find { |x| x["id"] == assignment.id }["delivery"]
          products = stop["items"].map { |i| i["product"] }
          assert_includes products, "Mesa"
          assert_not_includes products, "Silla cancelada"
        end

        test "claim_tracking toma el plan para el usuario actual" do
          @plan.update_columns(last_recorded_by_id: users(:two).id, last_seen_at: 1.minute.ago)

          patch claim_tracking_api_v1_driver_delivery_plan_path(@plan), headers: auth

          assert_response :success
          json = JSON.parse(response.body)
          assert json["ok"]
          assert_nil json["active_tracker"]
          assert_equal @driver.id, @plan.reload.last_recorded_by_id
        end
      end
    end
  end
end
