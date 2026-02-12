# app/controllers/pwa_controller.rb
class PwaController < ActionController::Base
  skip_forgery_protection

  def service_worker
    response.headers["Content-Type"] = "application/javascript; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render template: "pwa/service-worker", layout: false, formats: [:js]
  end

  def manifest
    response.headers["Content-Type"] = "application/manifest+json; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render template: "pwa/manifest", layout: false
  end
end
