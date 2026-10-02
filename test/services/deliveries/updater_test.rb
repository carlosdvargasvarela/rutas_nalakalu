require "test_helper"

class Deliveries::UpdaterTest < ActiveSupport::TestCase
  test "editar la referencia del chofer no cambia la de otras entregas con la misma dirección" do
    d1 = deliveries(:one)
    addr = d1.delivery_address
    original = addr.description
    d2 = Delivery.create!(d1.attributes.except("id", "tracking_token", "created_at", "updated_at"))

    params = ActionController::Parameters.new(
      delivery_address: { address: addr.address, description: "Referencia nueva", latitude: addr.latitude.to_s, longitude: addr.longitude.to_s },
      delivery: { delivery_address_id: addr.id.to_s, order_id: d1.order_id.to_s }
    )
    Deliveries::Updater.new(delivery: d1, params: params, current_user: users(:one)).call

    assert_equal "Referencia nueva", d1.reload.delivery_address.description
    assert_equal original, d2.reload.delivery_address.description
  end
end
