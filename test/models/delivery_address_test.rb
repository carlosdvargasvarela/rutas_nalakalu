require "test_helper"

class DeliveryAddressTest < ActiveSupport::TestCase
  test "stuck_at_default_coordinates? detects the map's fallback San José pin" do
    address = delivery_addresses(:one)
    address.latitude = DeliveryAddress::DEFAULT_MAP_LAT
    address.longitude = DeliveryAddress::DEFAULT_MAP_LNG

    assert address.stuck_at_default_coordinates?
    assert_includes address.address_errors, "Coordenadas no confirmadas (nunca se movió el pin del mapa)"
  end

  test "una nota con 'pendiente' no invalida una dirección válida" do
    address = delivery_addresses(:one)
    address.address = "C. Clínica Jorge Volio 1, Mercedes Norte, San Francisco, Heredia"
    address.latitude = 9.99
    address.longitude = -84.12
    address.description = "Pendiente de confirmar el horario de la oficina ese día."

    refute_includes address.address_errors, "Texto de dirección inválido"

    address.address = "pendiente"
    assert_includes address.address_errors, "Texto de dirección inválido"
  end

  test "stuck_at_default_coordinates? is false for real coordinates" do
    address = delivery_addresses(:one)
    address.latitude = 9.93
    address.longitude = -84.08

    refute address.stuck_at_default_coordinates?
  end

  test "stuck_at_default_coordinates scope finds addresses pinned at the map default" do
    address = delivery_addresses(:one)
    address.update_columns(latitude: DeliveryAddress::DEFAULT_MAP_LAT, longitude: DeliveryAddress::DEFAULT_MAP_LNG)

    assert_includes DeliveryAddress.stuck_at_default_coordinates, address
  end
end
