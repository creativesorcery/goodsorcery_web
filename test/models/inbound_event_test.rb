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
end
