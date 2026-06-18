require "test_helper"

class AuditActorTest < ActiveSupport::TestCase
  test "current resolves the user from PaperTrail's whodunnit" do
    PaperTrail.request(whodunnit: users(:one).id.to_s) do
      assert_equal users(:one), AuditActor.current
    end
  end

  test "current returns nil when there is no whodunnit set" do
    PaperTrail.request(whodunnit: nil) do
      assert_nil AuditActor.current
    end
  end

  test "current returns nil when whodunnit points to a non-existent user" do
    PaperTrail.request(whodunnit: "999999") do
      assert_nil AuditActor.current
    end
  end
end
