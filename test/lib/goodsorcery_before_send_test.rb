require "test_helper"

class GoodsorceryBeforeSendTest < ActiveSupport::TestCase
  setup { @before_send = GoodSorcery.configuration.before_send }

  test "drops errors from the events endpoints" do
    assert_nil @before_send.call(event(url: "https://app.goodsorcery.com/api/v1/events"))
    assert_nil @before_send.call(event(url: "https://app.goodsorcery.com/api/v1/events/batch"))
    assert_nil @before_send.call(event(url: "http://localhost:3000/api/v1/events?x=1"))
  end

  test "drops errors from the inbound event job" do
    assert_nil @before_send.call(event(transaction: "ProcessInboundEventJob"))
  end

  test "keeps every other error" do
    kept = event(url: "https://app.goodsorcery.com/api/v1/verify", transaction: "Api::V1::VerificationsController#show")
    assert_equal kept, @before_send.call(kept)
    assert_equal event(url: "https://app.goodsorcery.com/api/v1/eventsx"), @before_send.call(event(url: "https://app.goodsorcery.com/api/v1/eventsx"))
    assert_equal event(transaction: "IssueAlertJob"), @before_send.call(event(transaction: "IssueAlertJob"))
    assert_equal({ "level" => "error" }, @before_send.call({ "level" => "error" }))
  end

  private

  def event(url: nil, transaction: nil)
    { "level" => "error", "transaction" => transaction, "request" => (url && { "url" => url }) }.compact
  end
end
