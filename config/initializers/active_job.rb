# config/initializers/active_job.rb
# Configurar el adaptador de ActiveJob según disponibilidad de Redis

begin
  redis_url = ENV["REDIS_URL"] || "redis://localhost:6379/0"
  test_redis = Redis.new(url: redis_url, timeout: 1)
  test_redis.ping
  test_redis.close
  
  # Redis está disponible, usar Sidekiq
  Rails.application.config.active_job.queue_adapter = :sidekiq
  Rails.logger.info "ActiveJob configurado con Sidekiq"
rescue Redis::CannotConnectError, SocketError, Errno::ECONNREFUSED => e
  # Redis no disponible, usar async en desarrollo o inline en producción
  if Rails.env.development? || Rails.env.test?
    Rails.application.config.active_job.queue_adapter = :async
    Rails.logger.warn "Redis no disponible. ActiveJob configurado con :async (en memoria)"
  else
    Rails.application.config.active_job.queue_adapter = :inline
    Rails.logger.warn "Redis no disponible en producción. ActiveJob configurado con :inline (síncrono)"
  end
end
