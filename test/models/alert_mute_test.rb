require "test_helper"

class AlertMuteTest < ActiveSupport::TestCase
  setup do
    @user = users(:philip)
    @project = projects(:storefront)
  end

  test "a valid token names the member, the app and the stream" do
    mute = AlertMute.find_by_token(@user.alert_mute_token(@project))

    assert_equal memberships(:philip_acme), mute.membership
    assert_equal @user, mute.user
    assert_equal @project, mute.project
    assert_equal "alerts", mute.stream
    assert_not mute.digest?
  end

  test "apply mutes that app's alerts only" do
    mute = AlertMute.find_by_token(@user.alert_mute_token(@project))

    assert_not mute.applied?
    mute.apply

    assert mute.applied?
    assert_not memberships(:philip_acme).reload.receives_alerts?(@project)
    assert memberships(:philip_acme).receives_digest?(@project)
    assert memberships(:philip_acme).receives_alerts?(projects(:billing))
  end

  test "a digest token turns off the digest only" do
    AlertMute.find_by_token(@user.alert_mute_token(@project, stream: "digest")).apply

    membership = memberships(:philip_acme).reload
    assert_not membership.receives_digest?(@project)
    assert membership.receives_alerts?(@project)
  end

  test "an uptime token turns off that app's uptime alerts only" do
    mute = AlertMute.find_by_token(@user.alert_mute_token(@project, stream: "uptime"))
    assert mute.uptime?
    assert_not mute.applied?

    mute.apply

    membership = memberships(:philip_acme).reload
    assert_not membership.receives_uptime_alerts?(@project)
    assert membership.receives_alerts?(@project)
    assert membership.receives_digest?(@project)
    assert membership.receives_uptime_alerts?(projects(:billing))
    assert mute.applied?
  end

  test "an expired token is rejected" do
    token = @user.alert_mute_token(@project)

    travel AlertMute::EXPIRES_IN + 1.minute do
      assert_nil AlertMute.find_by_token(token)
    end
  end

  test "a tampered token is rejected" do
    token = @user.alert_mute_token(@project)
    data, digest = token.split("--")
    forged = Base64.strict_encode64(Base64.decode64(data).sub(@project.id.to_s, projects(:billing).id.to_s))

    assert_nil AlertMute.find_by_token("#{forged}--#{digest}")
    assert_nil AlertMute.find_by_token(token.reverse)
    assert_nil AlertMute.find_by_token("")
    assert_nil AlertMute.find_by_token(nil)
  end

  test "a token signed for another purpose is rejected" do
    token = AlertMute.verifier.generate({ "user_id" => @user.id, "project_id" => @project.id, "stream" => "alerts" }, purpose: :other)

    assert_nil AlertMute.find_by_token(token)
    assert_nil AlertMute.find_by_token(@user.email_verification_token)
  end

  test "a token only ever mutes its own app" do
    token = @user.alert_mute_token(projects(:billing))

    AlertMute.find_by_token(token).apply

    assert memberships(:philip_acme).reload.receives_alerts?(@project)
    assert_not memberships(:philip_acme).receives_alerts?(projects(:billing))
  end

  test "a token stops working once the person leaves the app's account" do
    token = users(:jo).alert_mute_token(@project)
    memberships(:jo_acme).destroy

    assert_nil AlertMute.find_by_token(token)
  end

  test "a token for an app in another account is rejected" do
    token = AlertMute.token_for(users(:outsider), @project)

    assert_nil AlertMute.find_by_token(token)
  end

  test "unknown streams are refused" do
    assert_raises(ArgumentError) { AlertMute.token_for(@user, @project, stream: "sms") }

    token = AlertMute.verifier.generate({ "user_id" => @user.id, "project_id" => @project.id, "stream" => "sms" },
                                        purpose: AlertMute::PURPOSE, expires_in: 1.day)
    assert_nil AlertMute.find_by_token(token)
  end

  test "the token carries ids only" do
    token = @user.alert_mute_token(@project)

    assert_no_match @user.email_address, Base64.decode64(token.split("--").first)
  end
end
