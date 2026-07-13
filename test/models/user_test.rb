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
end
