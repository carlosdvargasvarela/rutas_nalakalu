require "test_helper"

class DeliveryPlanTest < ActiveSupport::TestCase
  test "creating a plan records a created PlanEvent" do
    plan = DeliveryPlan.create!(week: "25", year: 2026, status: :draft)

    assert_equal "created", plan.plan_events.last.action
  end

  test "start! records a started PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)
    plan.deliveries.update_all(delivery_date: Date.current)

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.start!
    end

    assert_equal "started", plan.plan_events.last.action
  end

  test "start! rechaza un plan sin paradas" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)
    plan.delivery_plan_assignments.destroy_all

    assert_equal false, plan.start!
    assert_equal "routes_created", plan.reload.status
  end

  test "start! rechaza un plan cuya fecha de entrega no es hoy" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)
    assert_not_equal Date.current, plan.first_delivery_date

    refute plan.startable_today?
    assert_equal false, plan.start!
    assert_equal "routes_created", plan.reload.status
  end

  test "start! sí procede cuando la fecha de entrega es hoy" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)
    plan.deliveries.update_all(delivery_date: Date.current)

    assert plan.startable_today?
    assert plan.start!
    assert_equal "in_progress", plan.reload.status
  end

  test "finish! records a finished PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :in_progress)
    plan.delivery_plan_assignments.destroy_all

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.finish!
    end

    assert_equal "finished", plan.plan_events.last.action
  end

  test "abort! records an aborted PlanEvent" do
    plan = delivery_plans(:one)
    plan.update!(status: :routes_created)

    assert_difference -> { plan.plan_events.count }, 1 do
      plan.abort!
    end

    assert_equal "aborted", plan.plan_events.last.action
  end

  test "moving back to draft does not record a PlanEvent (no acción mapeada)" do
    plan = delivery_plans(:one)
    plan.update!(status: :sent_to_logistics)

    assert_no_difference -> { plan.plan_events.count } do
      plan.update!(status: :draft)
    end
  end

  test "PlanEvent actor is resolved via AuditActor when no current_user is in scope" do
    PaperTrail.request(whodunnit: users(:one).id.to_s) do
      plan = DeliveryPlan.create!(week: "40", year: 2026, status: :draft)

      assert_equal users(:one), plan.plan_events.last.actor
    end
  end

  test "assigning a driver to a confirmed draft plan with truck already set records routes_created exactly once (nested-save de-dup guard)" do
    plan = delivery_plans(:one)
    plan.update!(status: :draft, truck: :PRI)
    plan.deliveries.each { |d| d.update_columns(status: Delivery.statuses[:in_plan]) }

    assert_difference -> { plan.plan_events.where(action: "routes_created").count }, 1 do
      plan.update!(driver: users(:one))
    end
  end

  test "assigning only a driver (sin camión) no saca el plan de borrador" do
    plan = delivery_plans(:one)
    plan.update!(status: :draft, truck: nil)
    plan.deliveries.each { |d| d.update_columns(status: Delivery.statuses[:in_plan]) }

    plan.update!(driver: users(:one))

    assert plan.reload.status_draft?
  end

  test "asignar camión y conductor a un plan confirmado lo saca de borrador automáticamente" do
    plan = delivery_plans(:one)
    plan.update!(status: :draft, truck: nil, driver_id: nil)
    plan.deliveries.each { |d| d.update_columns(status: Delivery.statuses[:in_plan]) }

    plan.update!(driver: users(:one), truck: :PRI)

    assert plan.reload.status_routes_created?
  end

  test "removing a driver from a sent_to_logistics plan does not record a PlanEvent (draft is unmapped, and the nested-save guard would also prevent a double record if it were mapped)" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:sent_to_logistics], driver_id: users(:one).id)

    assert_no_difference -> { plan.plan_events.count } do
      plan.update!(driver_id: nil)
    end
  end

  test "recalculate_load_status! leaves a PaperTrail version on the plan" do
    plan = delivery_plans(:one)
    item = delivery_items(:one)
    item.update!(load_status: :loaded)
    versions_before = PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count

    plan.recalculate_load_status!

    assert_operator PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count, :>, versions_before
  end

  test "mark_all_loaded! leaves a PaperTrail version on each affected item" do
    plan = delivery_plans(:one)
    item = delivery_items(:one)
    item.update!(load_status: :unloaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      plan.mark_all_loaded!
    end

    assert_equal "loaded", item.reload.load_status
  end

  test "assigning a driver while all deliveries are confirmed updates status via update! and is visible in PaperTrail" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft], truck: DeliveryPlan.trucks[:PRI])
    plan.deliveries.update_all(status: Delivery.statuses[:in_plan])
    versions_before = PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count

    plan.update!(driver: users(:one))

    assert plan.reload.status_routes_created?
    assert_operator PaperTrail::Version.where(item_type: "DeliveryPlan", item_id: plan.id).count, :>, versions_before
    assert_equal "routes_created", plan.plan_events.last.action
  end

  test "belongs to last_recorded_by, optional" do
    plan = delivery_plans(:one)
    plan.update!(last_recorded_by: users(:two))

    assert_equal users(:two), plan.reload.last_recorded_by
  end

  test "updating last_recorded_by on a stale in-memory copy raises StaleObjectError" do
    plan = delivery_plans(:one)
    stale_copy = DeliveryPlan.find(plan.id)

    plan.update!(last_recorded_by: users(:one)) # bumps lock_version

    assert_raises(ActiveRecord::StaleObjectError) do
      stale_copy.update!(last_recorded_by: users(:two))
    end
  end

  test "resync_status! advances stray items on a lagging delivery whose assignment is already in_route" do
    assignment = delivery_plan_assignments(:one)
    assignment.update!(status: :in_route)
    assignment.delivery.update!(status: :in_plan)
    assignment.delivery.delivery_items.first.update!(status: :confirmed)

    fixed = assignment.delivery_plan.resync_status!

    assert_equal 1, fixed
    assert_equal "in_route", assignment.delivery.reload.status
  end

  test "status_needs_resync? is true while a delivery lags behind its in_route assignment" do
    assignment = delivery_plan_assignments(:one)
    assignment.update!(status: :in_route)
    assignment.delivery.update!(status: :in_plan)
    assignment.delivery.delivery_items.first.update!(status: :confirmed)

    assert assignment.delivery_plan.status_needs_resync?
  end

  test "resync_status! does not touch a delivery that is genuinely still pending (assignment not started)" do
    assignment = delivery_plan_assignments(:one)
    assignment.delivery.update!(status: :in_plan)

    fixed = assignment.delivery_plan.resync_status!

    assert_equal 0, fixed
    assert_equal "in_plan", assignment.delivery.reload.status
  end
end
