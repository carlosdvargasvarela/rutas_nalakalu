require "test_helper"

class Admin::VendorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
  end

  test "admin can list vendors" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    get admin_vendors_url
    assert_response :success
    assert_select "##{dom_id(vendor, :card)}"
  end

  test "edit renders inside the vendor_detail turbo frame without layout" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    get edit_admin_vendor_url(vendor), headers: {"Turbo-Frame" => "vendor_detail"}
    assert_response :success
    assert_select "turbo-frame#vendor_detail"
    assert_select "nav", false
  end

  test "edit does not nest the destroy form inside the main form" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    get edit_admin_vendor_url(vendor)
    assert_response :success
    # A <form> can't contain another <form>; the destroy button_to must be a
    # sibling of the main simple_form_for, not nested inside it.
    assert_select "form form", false
  end

  test "admin can destroy a vendor" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    assert_difference -> { Vendor.count } => -1 do
      delete admin_vendor_url(vendor)
    end
    assert_redirected_to admin_vendors_path
  end

  test "update via turbo_stream replaces the detail panel and the list card" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    patch admin_vendor_url(vendor),
      params: {vendor: {name: "Ferretería EPA Norte"}},
      as: :turbo_stream
    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_includes response.body, dom_id(vendor, :card)
    assert_includes response.body, "Ferretería EPA Norte"
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

  test "new renders inside the global modal frame when requested from it" do
    sign_in @admin
    get new_admin_vendor_url, headers: {"Turbo-Frame" => "modal"}
    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "[data-controller=vendor-address-list]"
  end

  test "create from the modal closes it and refreshes the vendor select" do
    sign_in @admin
    assert_difference -> { Vendor.count } => 1 do
      post admin_vendors_url,
        params: {
          vendor: {
            name: "Ferretería EPA",
            vendor_addresses_attributes: {"0" => {address: "San José", latitude: "9.93", longitude: "-84.08"}}
          }
        },
        headers: {"Turbo-Frame" => "modal"},
        as: :turbo_stream
    end
    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_includes response.body, 'target="modal"'
    assert_includes response.body, "vendor_address_select_container"
    assert_includes response.body, "Ferretería EPA"
  end

  test "edit from the modal renders inside the modal frame, not the workspace panel" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    get edit_admin_vendor_url(vendor), headers: {"Turbo-Frame" => "modal"}
    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "turbo-frame#vendor_detail", false
  end

  test "update from the modal closes it and refreshes the vendor select instead of the workspace panel" do
    vendor = Vendor.new(name: "Ferretería EPA")
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    vendor.save!

    sign_in @admin
    patch admin_vendor_url(vendor),
      params: {vendor: {name: "Ferretería EPA Norte"}},
      headers: {"Turbo-Frame" => "modal"},
      as: :turbo_stream
    assert_response :success
    assert_includes response.body, 'target="modal"'
    assert_includes response.body, "vendor_address_select_container"
    assert_not_includes response.body, "vendor_detail"
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
