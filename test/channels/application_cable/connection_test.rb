require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with an active session, identified by its user and session" do
    session = sessions(:alex_browser)
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:alex), connection.current_user
    assert_equal session, connection.current_session
  end

  test "Session#disconnect_live_updates addresses exactly this connection's internal channel" do
    session = sessions(:alex_browser)
    cookies.signed[:session_id] = session.id

    connect

    remote = ActionCable.server.remote_connections.where(current_user: session.user, current_session: session)
    assert_equal "action_cable/#{connection.connection_identifier}", remote.send(:internal_channel)
  end

  test "rejects a connection without a session" do
    assert_reject_connection { connect }
  end

  test "rejects an ended or expired session" do
    session = sessions(:alex_browser)
    cookies.signed[:session_id] = session.id
    session.update_columns(created_at: 31.days.ago)

    assert_reject_connection { connect }
  end
end
