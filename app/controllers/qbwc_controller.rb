class QbwcController < ActionController::Base
  include QBWC::Controller

  def authenticate(username, password)
    user = ENV["QB_USER"].to_s.strip
    pass = ENV["QB_PASS"].to_s.strip

    if username.to_s.strip == user && password.to_s.strip == pass
      [SecureRandom.uuid, nil]
    else
      Rails.logger.error "QB Auth Falló -> #{username}"
      ["", "nvu"]
    end
  end

  def server_version(_version)
    ""
  end

  def client_version(_version)
    ""
  end

  def connection_error(ticket, hresult, message)
    "done"
  end

  def close_connection(ticket)
    "OK"
  end
end
