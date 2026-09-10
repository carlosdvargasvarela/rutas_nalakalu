require "test_helper"

# Regresión para bugs encontrados en la auditoría de policies:
# - "logistic" (singular) comparado contra el enum real "logistics" (plural),
#   que nunca matcheaba y bloqueaba al rol logistics de varias acciones.
# - Scopes con joins/asociaciones copy-pasteadas de otro modelo que no existen
#   en el modelo real (delivery_plan_assignments en singular, order: :seller
#   sobre modelos sin esa asociación, driver_id en tablas que no lo tienen).
class PolicyRegressionsTest < ActiveSupport::TestCase
  setup do
    @logistics_user = users(:one)
    @logistics_user.update!(role: :logistics)

    @seller_user = users(:two)
    @seller_user.update!(role: :seller)

    @driver_user = users(:one)
  end

  test "DeliveryPlanPolicy allows logistics role" do
    assert DeliveryPlanPolicy.new(@logistics_user, DeliveryPlan).create?
    assert_includes DeliveryPlanPolicy::Scope.new(@logistics_user, DeliveryPlan).resolve, delivery_plans(:one)
  end

  test "DeliveryImportPolicy allows logistics role and scopes others by user_id without error" do
    assert DeliveryImportPolicy.new(@logistics_user, DeliveryImport).create?
    assert_nothing_raised { DeliveryImportPolicy::Scope.new(@seller_user, DeliveryImport).resolve.to_a }
  end

  test "DeliveryPlanAssignmentPolicy allows logistics role" do
    assert DeliveryPlanAssignmentPolicy.new(@logistics_user, DeliveryPlanAssignment).destroy?
  end

  test "OrderPolicy::Scope resolves for seller and driver without raising" do
    assert_nothing_raised { OrderPolicy::Scope.new(@seller_user, Order).resolve.to_a }
    assert_nothing_raised { OrderPolicy::Scope.new(@driver_user, Order).resolve.to_a }
  end

  test "DeliveryPolicy::Scope resolves for driver without raising" do
    assert_nothing_raised { DeliveryPolicy::Scope.new(@driver_user, Delivery).resolve.to_a }
  end

  test "DeliveryAddressPolicy resolves for seller and driver without raising" do
    assert_nothing_raised { DeliveryAddressPolicy.new(@driver_user, delivery_addresses(:one)).show? }
    assert_nothing_raised { DeliveryAddressPolicy::Scope.new(@seller_user, DeliveryAddress).resolve.to_a }
    assert_nothing_raised { DeliveryAddressPolicy::Scope.new(@driver_user, DeliveryAddress).resolve.to_a }
  end

  test "UserPolicy::Scope resolves without raising" do
    assert_nothing_raised { UserPolicy::Scope.new(@seller_user, User).resolve.to_a }
  end
end
