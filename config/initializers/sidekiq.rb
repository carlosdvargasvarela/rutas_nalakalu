# config/initializers/sidekiq.rb
redis_url = ENV.fetch('REDIS_URL', ENV.fetch('REDISCLOUD_URL', 'redis://localhost:6379/1'))

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  schedule_file = "config/sidekiq.yml"
  if File.exist?(schedule_file) && Sidekiq.server?
    Sidekiq::Scheduler.dynamic = true
    Sidekiq.schedule = YAML.load_file(schedule_file)[:schedule]
    Sidekiq::Scheduler.reload_schedule!
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end