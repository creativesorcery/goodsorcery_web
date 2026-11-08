require "test_helper"

class AuthorizedStreamsChannelTest < ActionCable::Channel::TestCase
  test "a member subscribes to the account projects stream" do
    subscribe_as users(:philip), [ accounts(:acme), :projects ]

    assert subscription.confirmed?
    assert_has_stream stream_name_from([ accounts(:acme), :projects ])
  end

  test "a member subscribes to project issue-list and setup streams" do
    subscribe_as users(:jo), [ projects(:storefront), :issues ]
    assert subscription.confirmed?
    assert_has_stream stream_name_from([ projects(:storefront), :issues ])

    subscribe_as users(:jo), [ projects(:marketing), :setup ]
    assert subscription.confirmed?
  end

  test "a member subscribes to an issue stream" do
    subscribe_as users(:philip), [ issues(:nomethod) ]

    assert subscription.confirmed?
    assert_has_stream stream_name_from([ issues(:nomethod) ])
  end

  test "an outsider is rejected from another account's account, project and issue streams" do
    [ [ accounts(:acme), :projects ], [ projects(:storefront), :issues ], [ projects(:storefront), :setup ], [ issues(:nomethod) ] ].each do |streamables|
      subscribe_as users(:outsider), streamables

      assert subscription.rejected?, "expected rejection for #{streamables.inspect}"
      assert_no_streams
    end
  end

  test "an outsider can subscribe to their own account's streams" do
    subscribe_as users(:outsider), [ projects(:umbrella_app), :issues ]

    assert subscription.confirmed?
  end

  test "a tampered signed stream name is rejected" do
    signed = Turbo::StreamsChannel.signed_stream_name([ projects(:storefront), :issues ])
    data, digest = signed.split("--")
    tampered = "#{Base64.strict_encode64(stream_name_from([ projects(:umbrella_app), :issues ]).to_json)}--#{digest}"

    stub_connection current_user: users(:outsider)
    subscribe signed_stream_name: tampered
    assert subscription.rejected?

    subscribe signed_stream_name: "#{data}--#{digest.reverse}"
    assert subscription.rejected?
  end

  test "an unsigned stream name is rejected even for a member" do
    stub_connection current_user: users(:philip)
    subscribe signed_stream_name: stream_name_from([ projects(:storefront), :issues ])

    assert subscription.rejected?
  end

  test "a name signed with another secret is rejected" do
    forged = ActiveSupport::MessageVerifier.new("not-the-app-secret").generate(stream_name_from([ projects(:storefront), :issues ]))

    stub_connection current_user: users(:philip)
    subscribe signed_stream_name: forged

    assert subscription.rejected?
  end

  test "a missing signed stream name is rejected" do
    stub_connection current_user: users(:philip)
    subscribe

    assert subscription.rejected?
  end

  test "a stream not anchored on an account, project or issue is rejected" do
    subscribe_as users(:philip), [ :global ]
    assert subscription.rejected?

    subscribe_as users(:philip), [ users(:philip) ]
    assert subscription.rejected?

    subscribe_as users(:philip), [ occurrences(:nomethod_latest) ]
    assert subscription.rejected?
  end

  test "a stream for a deleted record is rejected" do
    signed = Turbo::StreamsChannel.signed_stream_name([ issues(:nomethod), :issues ])
    issues(:nomethod).delete

    stub_connection current_user: users(:philip)
    subscribe signed_stream_name: signed

    assert subscription.rejected?
  end

  test "a still-valid signed name is rejected once the user loses membership" do
    signed = Turbo::StreamsChannel.signed_stream_name([ accounts(:acme), :projects ])
    memberships(:jo_acme).destroy!

    stub_connection current_user: users(:jo)
    subscribe signed_stream_name: signed

    assert subscription.rejected?
  end

  test "a connection without a user is rejected" do
    subscribe_as nil, [ accounts(:acme), :projects ]

    assert subscription.rejected?
  end

  private
    def subscribe_as(user, streamables)
      stub_connection current_user: user
      subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamables)
    end
end

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with a signed session cookie and identifies the user" do
    cookies.signed[:session_id] = sessions(:philip_browser).id

    connect

    assert_equal users(:philip), connection.current_user
  end

  test "rejects anonymous connections" do
    assert_reject_connection { connect }
  end

  test "rejects an unsigned or unknown session cookie" do
    cookies[:session_id] = sessions(:philip_browser).id.to_s
    assert_reject_connection { connect }

    cookies.signed[:session_id] = 0
    assert_reject_connection { connect }
  end
end

# The stock channel verifies the same never-expiring signed names without the
# membership check, and any client can name it in a subscribe command.
class TurboStreamsChannelTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "rejects even a correctly signed name, so a removed member cannot listen in" do
    signed = Turbo::StreamsChannel.signed_stream_name([ projects(:storefront), :issues ])

    [ users(:outsider), users(:philip) ].each do |user|
      stub_connection current_user: user
      subscribe signed_stream_name: signed

      assert subscription.rejected?, "expected rejection for #{user.name}"
      assert_no_streams
    end
  end
end
