require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
  end

  test "admin can regenerate a driver's api token" do
    driver = User.create!(name: "Conductor Test", email: "conductor@test.com", role: :driver, password: "Nalakalu.01")
    old_token = driver.api_token
    assert_not_nil old_token

    sign_in @admin
    patch regenerate_api_token_admin_user_url(driver)

    assert_redirected_to edit_admin_user_path(driver)
    assert_not_equal old_token, driver.reload.api_token
  end

  test "quick actions show the api token field only for drivers" do
    driver = User.create!(name: "Conductor Test", email: "conductor@test.com", role: :driver, password: "Nalakalu.01")
    seller = User.create!(name: "Vendedor Test", email: "vendedor@test.com", role: :seller, password: "Nalakalu.01", seller_code: "V1")

    sign_in @admin

    get edit_admin_user_url(driver)
    assert_select "input[readonly][value=?]", driver.api_token

    get edit_admin_user_url(seller)
    assert_select "input[readonly]", false
  end
end
