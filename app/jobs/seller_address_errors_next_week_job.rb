# app/jobs/seller_address_errors_next_week_job.rb
class SellerAddressErrorsNextWeekJob < ApplicationJob
  queue_as :default

  def perform(reference_date = Date.current)
    SellerReports::AddressErrorsNextWeek.generate_and_send!(reference_date: reference_date)
  end
end
