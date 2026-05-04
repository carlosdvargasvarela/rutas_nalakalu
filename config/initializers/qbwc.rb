QBWC.configure do |c|
  # Credenciales que pondrás en el archivo .qwc y en el Web Connector
  c.username = ENV.fetch("QBWC_USER", "admin")
  c.password = ENV.fetch("QBWC_PASS", "password123")

  # Dejar vacío para usar el archivo que esté abierto en QuickBooks
  c.company_file_path = ""

  # Versión QBXML compatible con QuickBooks Desktop 2024
  c.min_version = "13.0"

  # Tipo de QuickBooks (QuickBooks Financial Software, no POS)
  c.api = :qb

  # Almacenamiento en base de datos
  c.storage = :active_record

  # URL de soporte
  c.support_site_url = "https://rutas-nalakalu.com"

  # GUID único para identificar tu app ante QuickBooks
  c.owner_id = "{57F3B9B1-86F1-4fcc-B1EE-566DE1813D20}"

  # nil = solo corre manualmente desde el Web Connector (recomendado para pruebas)
  c.minutes_to_run = nil

  # En caso de error, detener el proceso
  c.on_error = :stop

  c.logger = Rails.logger
end
