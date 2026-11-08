require "test_helper"

class Apm::TraceIdTest < ActiveSupport::TestCase
  include ApmFixtureClock

  test "generate embeds the time and is a UUIDv7" do
    at = Time.utc(2026, 11, 4, 14, 32, 8.114r)
    id = Apm::TraceId.generate(at)
    assert Apm::TraceId.v7?(id)
    assert_equal at, Apm::TraceId.time(id)
  end

  test "uuid and time accept only well-formed ids" do
    assert_equal "0192f7af-9c1e-7a3b-8c2d-4e5f6a7b7f3a", Apm::TraceId.uuid("0192F7AF-9C1E-7A3B-8C2D-4E5F6A7B7F3A")
    assert_nil Apm::TraceId.uuid("nope")
    assert_nil Apm::TraceId.uuid(42)
    assert_nil Apm::TraceId.time(SecureRandom.uuid), "v4"
    assert_equal Time.utc(2024, 11, 4, 14, 58, 54, 110_000), Apm::TraceId.time("0192f7af-9c1e-7a3b-8c2d-4e5f6a7b7f3a")
  end
end
