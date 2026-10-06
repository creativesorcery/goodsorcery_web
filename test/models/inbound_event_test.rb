require "test_helper"

class InboundEventTest < ActiveSupport::TestCase
  test "received_at defaults to now" do
    freeze_time do
      event = InboundEvent.new
      assert_equal Time.current, event.received_at
    end
  end

  test "stale events are older than ten minutes" do
    assert_empty InboundEvent.stale

    travel 11.minutes do
      assert_equal [ inbound_events(:storefront_pending) ], InboundEvent.stale.to_a
    end
  end

  test "creating stores the body encrypted" do
    event = InboundEvent.create!(project: projects(:storefront), api_key: api_keys(:storefront_production),
      environment: "production", event_uuid: SecureRandom.uuid_v7, body: '{"user":{"email":"x@example.com"}}')

    raw = InboundEvent.connection.select_value("SELECT body FROM inbound_events WHERE id = #{event.id}")
    assert_no_match(/x@example\.com/, raw)
    assert_equal '{"user":{"email":"x@example.com"}}', event.reload.body
  end

  test "store_for inserts every event in one statement, encrypted, scoped by the credential" do
    credential = ApiKey.authenticate(FIXTURE_TOKENS[:storefront_staging])
    uuids = [ SecureRandom.uuid_v7, SecureRandom.uuid_v7 ]
    bodies = [ '{"user":{"email":"mara@example.com"}}', '{"password":"hunter2"}' ]

    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    stored = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      InboundEvent.store_for(credential, uuids.zip(bodies))
    end

    assert_equal 1, statements.size
    assert stored.all?(&:persisted?)
    stored.each do |event|
      raw = InboundEvent.connection.select_value("SELECT body FROM inbound_events WHERE id = #{event.id}")
      assert_no_match(/mara|hunter2/, raw)
      assert_match(/"p":/, raw, "Active Record encryption envelope")
    end
    rows = InboundEvent.where(id: stored.map(&:id)).order(:id)
    assert_equal bodies, rows.map(&:body)
    assert_equal uuids, rows.map(&:event_uuid)
    assert_equal [ [ projects(:storefront).id, api_keys(:storefront_staging).id, "staging" ] ],
                 rows.map { [ it.project_id, it.api_key_id, it.environment ] }.uniq
  end
end
