require "test_helper"

class VendorTest < ActiveSupport::TestCase
  test "invalid without at least one address" do
    vendor = Vendor.new(name: "Proveedor Test")
    assert vendor.invalid?
    assert_includes vendor.errors[:vendor_addresses], "debe tener al menos una dirección"
  end

  test "valid with name, contact and address with coordinates" do
    vendor = Vendor.new(name: "Proveedor Test")
    vendor.vendor_contacts.build(name: "Juan Pérez", phone: "8888-8888", is_primary: true)
    vendor.vendor_addresses.build(address: "San José", latitude: 9.93, longitude: -84.08)
    assert vendor.valid?
  end

  test "vendor address invalid without coordinates" do
    vendor = Vendor.new(name: "Proveedor Test")
    address = vendor.vendor_addresses.build(address: "Sin coordenadas")
    address.valid?
    assert_includes address.errors[:base], "La dirección debe tener coordenadas"
  end
end
