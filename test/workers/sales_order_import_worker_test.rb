require "test_helper"
require "minitest/mock"

class SalesOrderImportWorkerTest < ActiveSupport::TestCase
  setup do
    @worker = SalesOrderImportWorker.new
  end

  test "advances qb_sync_from_date once the iterator is exhausted" do
    response = {"sales_order_ret" => nil, "xml_attributes" => {"iteratorRemainingCount" => "0"}}

    ProcessQuickbooksXmlJob.stub(:perform_async, ->(*) { flunk "no orders to enqueue" }) do
      @worker.handle_response(response, nil, nil, nil, nil)
    end

    assert AppSetting.get("qb_sync_from_date").present?
  end

  test "does not advance qb_sync_from_date while more pages remain" do
    response = {"sales_order_ret" => nil, "xml_attributes" => {"iteratorRemainingCount" => "5"}}

    @worker.handle_response(response, nil, nil, nil, nil)

    assert_nil AppSetting.get("qb_sync_from_date")
  end
end
