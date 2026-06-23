require "test_helper"

class DetectorKeywordListTest < ActiveSupport::TestCase
  test "requires a detector and a list_name" do
    list = DetectorKeywordList.new(values_list: ["foo"])
    assert_not list.valid?
    assert_includes list.errors.attribute_names, :detector
    assert_includes list.errors.attribute_names, :list_name
  end

  test "list_name must be unique within the same detector" do
    DetectorKeywordList.create!(detector: "service_case", list_name: "keywords", values_list: ["a"])
    dup = DetectorKeywordList.new(detector: "service_case", list_name: "keywords", values_list: ["b"])

    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :list_name
  end

  test "the same list_name is allowed across different detectors" do
    DetectorKeywordList.create!(detector: "service_case", list_name: "keywords", values_list: ["a"])
    other = DetectorKeywordList.new(detector: "repair_service", list_name: "keywords", values_list: ["b"])

    assert other.valid?
  end

  test "serializes values_list as an array" do
    list = DetectorKeywordList.create!(detector: "service_case", list_name: "keywords", values_list: ["caso de servicio"])

    assert_equal ["caso de servicio"], DetectorKeywordList.find(list.id).values_list
  end
end
