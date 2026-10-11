require "test_helper"

class NotificationPreferenceTest < ActiveSupport::TestCase
  test "one row per member and app" do
    duplicate = NotificationPreference.new(membership: memberships(:jo_acme), project: projects(:billing))

    assert_not duplicate.valid?
  end

  test "the app must belong to the member's account" do
    preference = NotificationPreference.new(membership: memberships(:jo_acme), project: projects(:umbrella_app))

    assert_not preference.valid?
    assert_includes preference.errors[:project], "must belong to the member's account"
  end

  test "receives? reads the switch for each stream" do
    preference = notification_preferences(:jo_billing)

    assert_not preference.receives?("alerts")
    assert preference.receives?(:digest)
  end

  test "stopped_attributes turns one stream off" do
    assert_equal({ alerts_muted: true }, NotificationPreference.stopped_attributes("alerts"))
    assert_equal({ digest_enabled: false }, NotificationPreference.stopped_attributes(:digest))
    assert_raises(KeyError) { NotificationPreference.stopped_attributes("sms") }
  end
end
