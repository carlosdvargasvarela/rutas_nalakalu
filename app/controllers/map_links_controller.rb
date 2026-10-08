class MapLinksController < ApplicationController
  # POST /map_links/resolve  url=<enlace de Google Maps / Apple Maps / Waze>
  def resolve
    skip_authorization
    lat, lng = MapUrlResolver.call(params[:url])

    if lat
      render json: {lat: lat, lng: lng}
    else
      render json: {error: "No se pudieron obtener coordenadas de ese enlace"}, status: :unprocessable_entity
    end
  end
end
