require "test_helper"

class TrackingPolicyTest < ActiveSupport::TestCase
  def test_index_true_for_non_driver_roles
    %w[admin manager production_manager seller logistics proveeduria].each do |role|
      user = users(:one)
      user.role = role
      assert TrackingPolicy.new(user, nil).index?, "#{role} debería poder ver /tracking"
    end
  end

  def test_index_false_for_driver
    user = users(:one)
    user.role = "driver"
    refute TrackingPolicy.new(user, nil).index?
  end
end
