require "test_helper"

class Admin::VendorContactsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    @vendor = Vendor.new(name: "Ferretería EPA")
    @vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    @vendor.save!
  end

  test "admin can add a contact via turbo_stream" do
    sign_in @admin
    assert_difference -> { VendorContact.count } => 1 do
      post admin_vendor_vendor_contacts_url(@vendor),
        params: {vendor_contact: {name: "Juan Pérez", phone: "8888-8888", is_primary: "1"}},
        as: :turbo_stream
    end
    assert_response :success
    assert_equal "Juan Pérez", @vendor.vendor_contacts.last.name
  end

  test "rejects a contact without a name" do
    sign_in @admin
    assert_no_difference -> { VendorContact.count } do
      post admin_vendor_vendor_contacts_url(@vendor),
        params: {vendor_contact: {name: "", phone: "8888-8888"}},
        as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "admin can update a contact" do
    contact = @vendor.vendor_contacts.create!(name: "Juan Pérez", phone: "8888-8888")

    sign_in @admin
    patch admin_vendor_vendor_contact_url(@vendor, contact),
      params: {vendor_contact: {phone: "7777-7777"}},
      as: :turbo_stream
    assert_response :success
    assert_equal "7777-7777", contact.reload.phone
  end

  test "admin can delete a contact" do
    contact = @vendor.vendor_contacts.create!(name: "Juan Pérez", phone: "8888-8888")

    sign_in @admin
    assert_difference -> { VendorContact.count } => -1 do
      delete admin_vendor_vendor_contact_url(@vendor, contact), as: :turbo_stream
    end
    assert_response :success
  end
end
