# app/controllers/delivery_addresses_controller.rb
class DeliveryAddressesController < ApplicationController
  def show
    @address = DeliveryAddress.find(params[:id])
    authorize @address

    respond_to do |format|
      format.json do
        render json: {
          id: @address.id,
          latitude: @address.latitude,
          longitude: @address.longitude,
          plus_code: @address.plus_code,
          address: @address.address,
          description: @address.description
        }
      end
    end
  end

  def create
    authorize DeliveryAddress
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
