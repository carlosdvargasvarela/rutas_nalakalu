Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }

  schedule_file = "config/sidekiq.yml"
  if File.exist?(schedule_file) && Sidekiq.server?
    Sidekiq::Scheduler.dynamic = true
    Sidekiq.schedule = YAML.load_file(schedule_file)[:schedule]
    Sidekiq::Scheduler.reload_schedule!
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end