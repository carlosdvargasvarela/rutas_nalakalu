class PwaController < ActionController::Base
  skip_forgery_protection
  skip_before_action :verify_authenticity_token

  def service_worker
    response.headers["Content-Type"] = "application/javascript; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render template: "pwa/service-worker", layout: false, formats: [:js]
  end

  def manifest
    response.headers["Content-Type"] = "application/manifest+json; charset=utf-8"
    response.headers["Cache-Control"] = "public, max-age=3600"

    render json: {
      name: "NaLakalu - Chofer",
      short_name: "Chofer",
      id: "/driver/",
      start_url: "/driver/delivery_plans",
      scope: "/driver/",
      display: "standalone",
      orientation: "portrait",
      background_color: "#ffffff",
      theme_color: "#667eea",
      icons: [
        {
          src: "/icons/icon-192.png",
          sizes: "192x192",
          type: "image/png",
          purpose: "any maskable"
        },
        {
          src: "/icons/icon-512.png",
          sizes: "512x512",
          type: "image/png",
          purpose: "any maskable"
        }
      ]
    }
  end
end
