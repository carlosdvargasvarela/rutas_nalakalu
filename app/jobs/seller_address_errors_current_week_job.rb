# app/jobs/seller_address_errors_current_week_job.rb
class SellerAddressErrorsCurrentWeekJob < ApplicationJob
  queue_as :default

  def perform(reference_date = Date.current)
    SellerReports::AddressErrorsCurrentWeek.generate_and_send!(reference_date: reference_date)
  end
end