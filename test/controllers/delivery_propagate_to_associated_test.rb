require "test_helper"

class DeliveryPropagateToAssociatedTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin

    @source = deliveries(:one)
    @valid_target = deliveries(:two)
    @invalid_target = @source.order.deliveries.create!(
      delivery_address: @source.delivery_address,
      delivery_date: Date.current,
      status: :scheduled
    )

    group = DeliveryGroup.create!
    group.deliveries << @source << @valid_target << @invalid_target
  end

  test "propagates the selected fields to every valid target inside a transaction" do
    @source.update!(contact_name: "Nuevo contacto")

    patch propagate_to_associated_delivery_url(@source), params: {
      fields: ["contact_name"],
      delivery_ids: [@valid_target.id]
    }

    assert_response :success
    assert_equal "Nuevo contacto", @valid_target.reload.contact_name
  end

  test "rolls back every target if one of them fails to save" do
    @source.update!(contact_name: "Nuevo contacto")
    original_valid_name = @valid_target.contact_name

    # Deja @invalid_target en un estado que ya no pasa las validaciones del
    # modelo (sin fecha) sin pasar por save!, para forzar que su update!
    # dentro de propagate_to_associated falle igual que fallaría con
    # cualquier otra violación real — y así comprobar que la transacción
    # deshace también el cambio ya aplicado a @valid_target.
    @invalid_target.update_column(:delivery_date, nil)

    patch propagate_to_associated_delivery_url(@source), params: {
      fields: ["contact_name"],
      delivery_ids: [@valid_target.id, @invalid_target.id]
    }

    assert_response :unprocessable_entity
    assert_equal original_valid_name, @valid_target.reload.contact_name
  end
end
