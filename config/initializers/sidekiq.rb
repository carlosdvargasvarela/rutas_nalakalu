# config/sidekiq.rb
require "sidekiq"
require "sidekiq-scheduler"

redis_url =
  ENV["REDIS_TLS_URL"] || # Heroku puede darte este si tu plan lo expone
  ENV["REDIS_URL"]      || # Heroku Redis mini
  ENV["REDISCLOUD_URL"] || # RedisCloud fallback
  "redis://localhost:6379/0" # Default para development

Sidekiq.configure_server do |config|
  config.redis = {
    url: redis_url,
    ssl_params: (redis_url.start_with?("rediss://") ? { verify_mode: OpenSSL::SSL::VERIFY_NONE } : {})
  }

  # ⬅️ AGREGAR: Configuración de sidekiq-scheduler
  config.on(:startup) do
    Sidekiq.schedule = YAML.load_file(File.expand_path("../../sidekiq_schedule.yml", __FILE__))
    SidekiqScheduler::Scheduler.instance.reload_schedule!
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: redis_url,
    ssl_params: (redis_url.start_with?("rediss://") ? { verify_mode: OpenSSL::SSL::VERIFY_NONE } : {})
  }
end
