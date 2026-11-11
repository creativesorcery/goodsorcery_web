# Asserting that a browser session's Action Cable connection is told to
# disconnect (Session#disconnect_live_updates): RemoteConnections broadcasts
# to the connection's internal channel, named after its identifiers.
module CableTestHelper
  include ActionCable::TestHelper

  def cable_connection_channel(session)
    ActionCable.server.remote_connections.where(current_user: session.user, current_session: session).send(:internal_channel)
  end

  def assert_cable_disconnected(session)
    assert_equal [ { "type" => "disconnect", "reconnect" => true } ],
                 broadcasts(cable_connection_channel(session)).map { JSON.parse(it) },
                 "expected session #{session.id}'s live-update connection to be closed"
  end

  def assert_cable_not_disconnected(session)
    assert_empty broadcasts(cable_connection_channel(session)), "session #{session.id}'s connection was closed"
  end
end
