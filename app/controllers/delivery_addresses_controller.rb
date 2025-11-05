# app/controllers/delivery_addresses_controller.rb
class DeliveryAddressesController < ApplicationController
  def create
    @address = DeliveryAddress.new(address_params)
    if @address.save
      redirect_back fallback_location: root_path, notice: "Dirección agregada correctamente."
    else
      redirect_back fallback_location: root_path, alert: "Error al agregar dirección: #{@address.errors.full_messages.to_sentence}"
    end
  end

  private

  def address_params
    params.require(:delivery_address).permit(:address, :description, :latitude, :longitude, :plus_code, :client_id)
  end
end
