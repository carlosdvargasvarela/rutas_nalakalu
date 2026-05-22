require "test_helper"

class Production::DeliveryItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @item = delivery_items(:one)
    @user = users(:one)
    @user.update!(role: :logistics, email: "logistica@test.com",
                  password: "password123", password_confirmation: "password123")
    sign_in @user
  end

  test "add_note actualiza las notas del item via turbo_stream" do
    patch add_note_production_delivery_item_path(@item),
      params: { note: "Faltó en bodega" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "Faltó en bodega", @item.reload.notes
  end

  test "add_note requiere autenticación" do
    sign_out @user
    patch add_note_production_delivery_item_path(@item),
      params: { note: "cualquier cosa" }
    assert_response :redirect
  end
end
