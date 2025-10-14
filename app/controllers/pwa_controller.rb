class PwaController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :manifest, :service_worker, :offline ]
  skip_after_action :verify_authorized, only: [ :manifest, :service_worker, :offline ]

  def manifest
    render json: {
      name: "NaLakalu Rutas",
      short_name: "NaLakalu",
      description: "Sistema de rutas de entrega para choferes",
      start_url: "/",
      display: "standalone",
      background_color: "#ffffff",
      theme_color: "#0d6efd",
      orientation: "portrait",
      icons: [
        {
          src: view_context.asset_path("icons/icon-192.png"),
          sizes: "192x192",
          type: "image/png",
          purpose: "any maskable"
        },
        {
          src: view_context.asset_path("icons/icon-512.png"),
          sizes: "512x512",
          type: "image/png",
          purpose: "any maskable"
        }
      ]
    }
  end

  def service_worker
    render template: "pwa/service_worker", layout: false, content_type: "application/javascript"
  end

  def offline
    render "pwa/offline", layout: "application"
  end
end
