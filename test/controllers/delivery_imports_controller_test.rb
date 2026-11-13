require "test_helper"

class DeliveryImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "upload page links to the template and the template downloads" do
    get new_delivery_import_url
    assert_response :success
    assert_select "a[href=?]", template_delivery_imports_path

    get template_delivery_imports_url
    assert_response :success
    assert_match "plantilla_entregas.xlsx", response.headers["Content-Disposition"]
  end
end
