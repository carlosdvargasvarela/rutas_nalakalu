# config/sidekiq.rb
redis_url =
  ENV["REDIS_TLS_URL"] || # Heroku puede darte este si tu plan lo expone
  ENV["REDIS_URL"]      || # Heroku Redis mini
  ENV["REDISCLOUD_URL"] || # RedisCloud fallback
  "redis://localhost:6379/0" # Default para development

# Solo configurar Sidekiq si Redis está disponible
begin
  # Intentar conectar para verificar disponibilidad
  test_redis = Redis.new(url: redis_url, timeout: 1)
  test_redis.ping
  test_redis.close

  Sidekiq.configure_server do |config|
    config.redis = {
      url: redis_url,
      ssl_params: (redis_url.start_with?("rediss://") ? { verify_mode: OpenSSL::SSL::VERIFY_NONE } : {})
    }
  end

  Sidekiq.configure_client do |config|
    config.redis = {
      url: redis_url,
      ssl_params: (redis_url.start_with?("rediss://") ? { verify_mode: OpenSSL::SSL::VERIFY_NONE } : {})
    }
  end
rescue Redis::CannotConnectError, SocketError, Errno::ECONNREFUSED => e
  Rails.logger.warn "Redis no está disponible: #{e.message}. Sidekiq no se configurará."
  # En desarrollo sin Redis, los jobs se ejecutarán de forma síncrona
  if Rails.env.development?
    Rails.logger.info "Ejecutando en modo sin Redis - los jobs se ejecutarán síncronamente"
  end
end
