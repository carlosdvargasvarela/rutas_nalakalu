require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "proveeduria has the same permissions as production_manager" do
    user = User.new(role: :proveeduria)
    assert user.proveeduria?
    assert user.production_manager?
    assert_equal "Proveeduría", user.display_role
  end

  test "production_manager is not proveeduria" do
    user = User.new(role: :production_manager)
    assert user.production_manager?
    assert_not user.proveeduria?
  end

  test "proveeduria sees admin views but is not admin" do
    assert User.new(role: :proveeduria).sees_admin_views?
    assert User.new(role: :admin).sees_admin_views?
    assert_not User.new(role: :production_manager).sees_admin_views?
    assert_not User.new(role: :proveeduria).admin?
  end
end
