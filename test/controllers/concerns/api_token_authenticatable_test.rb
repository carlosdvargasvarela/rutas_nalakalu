require "test_helper"

# ponytail: auth behavior tested end-to-end in api/v1/driver/*_controller_test.rb
class ApiTokenAuthenticatableTest < ActiveSupport::TestCase
  test "User model has api_token attribute" do
    user = User.new
    assert_respond_to user, :api_token
    assert_respond_to user, :api_token=
  end

  test "ApiTokenAuthenticatable is a module with the expected methods" do
    assert ApiTokenAuthenticatable.is_a?(Module)
    assert ApiTokenAuthenticatable.private_method_defined?(:authenticate_api_token!)
    assert ApiTokenAuthenticatable.private_method_defined?(:current_user)
  end

  test "api_token index is unique" do
    index = ActiveRecord::Base.connection.indexes(:users).find { |i| i.columns == ["api_token"] }
    assert index, "Falta índice en users.api_token"
    assert index.unique, "El índice de api_token debe ser único"
  end
end
