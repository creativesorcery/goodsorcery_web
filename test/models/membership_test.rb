require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  include CableTestHelper

  test "roles" do
    assert memberships(:alex_acme).owner?
    assert memberships(:jo_acme).member?
    assert_not Membership.new(account: accounts(:acme), user: users(:outsider), role: "admin").valid?
  end

  test "a user joins an account only once" do
    duplicate = Membership.new(account: accounts(:acme), user: users(:jo))
    assert_not duplicate.valid?
  end

  test "removing a member ends their sessions in that account" do
    session = users(:jo).sessions.create!(account: accounts(:acme))

    memberships(:jo_acme).destroy

    assert_not Session.exists?(session.id)
    assert_not accounts(:acme).accessible_by?(users(:jo))
  end

  test "removing a member closes the live-update connections of their sessions in that account only" do
    in_account = users(:jo).sessions.create!(account: accounts(:acme))
    elsewhere = users(:jo).sessions.create!(account: accounts(:umbrella))
    teammate = sessions(:alex_browser)

    memberships(:jo_acme).destroy

    assert_cable_disconnected in_account
    assert_cable_not_disconnected elsewhere
    assert_cable_not_disconnected teammate
  end

  test "without a saved preference a member gets alerts and the digest" do
    membership = memberships(:alex_acme)
    preference = membership.notification_preference_for(projects(:storefront))

    assert preference.new_record?
    assert membership.receives_alerts?(projects(:storefront))
    assert membership.receives_digest?(projects(:storefront))
    assert membership.receives_uptime_alerts?(projects(:storefront))
    assert_empty membership.notification_preferences.reload, "the default is never saved"
  end

  test "muting an app's alerts keeps its digest" do
    membership = memberships(:jo_acme)

    assert_not membership.receives_alerts?(projects(:billing))
    assert membership.receives_digest?(projects(:billing))
    assert membership.receives_alerts?(projects(:storefront))
  end

  test "muting an app's uptime alerts keeps its issue alerts, and the reverse" do
    membership = memberships(:jo_acme)
    assert membership.receives_uptime_alerts?(projects(:billing)), "jo muted billing's issue alerts only"

    membership.update_notification_preference(projects(:storefront), uptime_alerts_muted: true)
    assert_not membership.receives_uptime_alerts?(projects(:storefront))
    assert membership.receives_alerts?(projects(:storefront))
    assert_equal [ memberships(:alex_acme) ], accounts(:acme).memberships.receiving_uptime_alerts_for(projects(:storefront)).to_a
  end

  test "an unverified address receives nothing" do
    membership = memberships(:jo_acme)
    membership.user.update!(email_verified_at: nil)

    assert_not membership.receives_alerts?(projects(:storefront))
    assert_not membership.receives_digest?(projects(:storefront))
    assert_not membership.receives_uptime_alerts?(projects(:storefront))
  end

  test "update_notification_preference creates the row once, then updates it" do
    membership = memberships(:alex_acme)

    assert_difference -> { NotificationPreference.count }, 1 do
      membership.update_notification_preference(projects(:storefront), alerts_muted: true)
      membership.update_notification_preference(projects(:storefront), digest_enabled: false)
    end

    preference = membership.notification_preferences.find_by!(project: projects(:storefront))
    assert preference.alerts_muted?
    assert_not preference.digest_enabled?
  end

  test "leaving the account deletes the member's preferences" do
    preference = notification_preferences(:jo_billing)

    memberships(:jo_acme).destroy

    assert_not NotificationPreference.exists?(preference.id)
  end
end
