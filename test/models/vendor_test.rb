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

  test "today_hours returns the business hour matching the current day" do
    vendor = Vendor.new(name: "Proveedor Test")
    vendor.vendor_business_hours.build(day_of_week: Date.current.wday, opens_at: "08:00", closes_at: "17:00")

    assert_equal "8:00 AM - 5:00 PM", vendor.today_hours.label
  end

  test "business hour invalid without opens_at/closes_at unless closed" do
    hour = VendorBusinessHour.new(day_of_week: 1)
    hour.valid?
    assert_includes hour.errors[:opens_at], "no puede estar en blanco"

    hour.closed = true
    hour.valid?
    assert_empty hour.errors[:opens_at]
  end
end
