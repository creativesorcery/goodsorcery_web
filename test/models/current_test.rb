require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  teardown { Current.reset }

  test "user and account come from the session" do
    Current.session = sessions(:alex_browser)

    assert_equal users(:alex), Current.user
    assert_equal accounts(:acme), Current.account
  end

  test "nil without a session" do
    assert_nil Current.user
    assert_nil Current.account
  end
end
