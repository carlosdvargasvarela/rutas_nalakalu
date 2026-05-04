QBWC.configure do |c|
  c.username = ENV.fetch("QB_USER", "admin")
  c.password = ENV.fetch("QB_PASS", "123456")
  c.company_file_path = ""
  c.min_version = "13.0"
  c.api = :qb
  c.storage = :active_record
  c.support_site_url = "https://rutas-nalakalu.com"
  c.owner_id = "{57F3B9B1-86F1-4fcc-B1EE-566DE1813D20}"
  c.minutes_to_run = nil
  c.on_error = :stop
  c.logger = Rails.logger
end
