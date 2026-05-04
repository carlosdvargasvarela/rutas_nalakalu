class QbwcController < ApplicationController
  include QBWC::Controller

  skip_before_action :authenticate_user!
  skip_after_action :verify_authorized

  def authenticate(username, password)
    expected_user = ENV.fetch("QB_USER", "admin").strip
    expected_pass = ENV.fetch("QB_PASS", "Acesa2023").strip

    if username.to_s.strip == expected_user && password.to_s.strip == expected_pass
      [SecureRandom.uuid, nil]
    else
      Rails.logger.warn "QB AUTH FAILED -> recibido: #{username} / #{password}"
      ["", "nvu"]
    end
  end
end
