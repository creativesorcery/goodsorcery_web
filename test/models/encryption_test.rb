require "test_helper"

# Captured data must be ciphertext at rest, including rows written by bulk inserts.
class EncryptionTest < ActiveSupport::TestCase
  test "fixture rows are stored encrypted" do
    assert_ciphertext Occurrence, occurrences(:nomethod_latest).id, :payload, "mara@example.com"
    assert_ciphertext ApiKey, api_keys(:storefront_production).id, :token, FIXTURE_TOKENS[:storefront_production]
    assert_ciphertext InboundEvent, inbound_events(:storefront_pending).id, :body, "mara@example.com"
    assert_ciphertext IssueActivity, issue_activities(:note).id, :body, "CartTotal"
  end

  test "encrypted attributes round-trip" do
    assert_match(/mara@example\.com/, occurrences(:nomethod_latest).payload)
    assert_equal FIXTURE_TOKENS[:storefront_production], api_keys(:storefront_production).token
    assert_equal "Mobile Safari", issue_tag_counts(:nomethod_browser_safari).value
  end

  test "tag values are encrypted" do
    raw = IssueTagCount.connection.select_values("SELECT value FROM issue_tag_counts")
    assert raw.none? { |value| value.include?("Mobile Safari") }
  end

  test "insert_all and upsert_all encrypt" do
    issue = issues(:card_error)
    Occurrence.insert_all([ {
      issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: Time.current,
      received_at: Time.current, environment: "production", level: "error", payload: { user: { email: "bulk@example.com" } }.to_json
    } ])
    IssueTagCount.upsert_all([ { issue_id: issue.id, key: "user", value_digest: "f" * 64, value: "bulk@example.com", count: 1 } ],
      unique_by: %i[issue_id key value_digest])

    assert_no_match(/bulk@example/, Occurrence.connection.select_value("SELECT payload FROM occurrences ORDER BY id DESC LIMIT 1"))
    assert_no_match(/bulk@example/, IssueTagCount.connection.select_value("SELECT value FROM issue_tag_counts WHERE key = 'user'"))
    assert_equal "bulk@example.com", IssueTagCount.find_by!(key: "user").value
  end

  test "unencrypted data is not readable" do
    assert_not ActiveRecord::Encryption.config.support_unencrypted_data
  end

  private
    def assert_ciphertext(model, id, column, plaintext)
      raw = model.connection.select_value(model.where(id:).select(column).to_sql)
      assert raw.present?
      assert_not_includes raw, plaintext
    end
end
