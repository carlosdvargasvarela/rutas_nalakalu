# app/jobs/current_week_unconfirmed_deliveries_job.rb
class CurrentWeekUnconfirmedDeliveriesJob < ApplicationJob
  queue_as :default

  def perform(reference_date = Date.current)
    AdminReports::CurrentWeekUnconfirmedDeliveries.generate_and_send!(reference_date: reference_date)
  end
end