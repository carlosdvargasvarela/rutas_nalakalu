require "test_helper"

class Admin::VendorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
  end

  test "admin can list vendors" do
    sign_in @admin
    get admin_vendors_url
    assert_response :success
  end

  test "admin can create a vendor with a contact and address" do
    sign_in @admin
    assert_difference -> { Vendor.count } => 1, -> { VendorContact.count } => 1, -> { VendorAddress.count } => 1 do
      post admin_vendors_url, params: {
        vendor: {
          name: "Ferretería EPA",
          vendor_contacts_attributes: {"0" => {name: "Juan Pérez", phone: "8888-8888", is_primary: "1"}},
          vendor_addresses_attributes: {"0" => {address: "San José", latitude: "9.93", longitude: "-84.08"}}
        }
      }
    end
    assert_redirected_to admin_vendors_path
  end

  test "proveeduria can create a vendor but cannot edit or destroy one" do
    @admin.update!(role: :proveeduria)
    sign_in @admin

    assert_difference -> { Vendor.count } => 1 do
      post admin_vendors_url, params: {
        vendor: {
          name: "Distribuidora Central",
          vendor_addresses_attributes: {"0" => {address: "Heredia", latitude: "10.0", longitude: "-84.1"}}
        }
      }
    end

    vendor = Vendor.last
    get edit_admin_vendor_url(vendor)
    assert_redirected_to root_path

    delete admin_vendor_url(vendor)
    assert_redirected_to root_path
    assert Vendor.exists?(vendor.id)
  end
end
