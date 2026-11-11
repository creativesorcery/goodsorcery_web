require "test_helper"

class PersonalAccessTokenTest < ActiveSupport::TestCase
  def create_token(**attributes)
    users(:jo).personal_access_tokens.create!({ account: accounts(:acme), name: "Laptop" }.merge(attributes))
  end

  test "generates a gs_pat_ token of at least 32 random bytes and stores only its digest" do
    token = create_token

    assert_match(/\Ags_pat_[A-Za-z0-9_-]{43}\z/, token.token)
    assert_equal OpenSSL::Digest::SHA256.hexdigest(token.token), token.token_digest
    assert_equal token.token.last(4), token.token_last4
    assert_equal "gs_pat_…#{token.token_last4}", token.masked_token

    row = PersonalAccessToken.connection.select_one("SELECT * FROM personal_access_tokens WHERE id = #{token.id}")
    assert_not row.values.map(&:to_s).any? { |value| value.include?(token.token) }
    assert_nil PersonalAccessToken.find(token.id).token, "the plaintext exists only on the creating instance"
  end

  test "tokens are unique" do
    assert_not_equal create_token.token, create_token(name: "Other").token
  end

  test "scopes always include read and drop unknown ones" do
    assert_equal %w[read], create_token(scopes: []).scopes
    assert_equal %w[read triage], create_token(scopes: %w[triage admin]).scopes
    assert_equal %w[read triage request_data], create_token(scopes: %w[request_data triage read]).scopes.sort_by { PersonalAccessToken::SCOPES.index(it) }
  end

  test "authenticates a valid token and nothing else" do
    token = create_token

    assert_equal token, PersonalAccessToken.authenticate(token.token)
    assert_nil PersonalAccessToken.authenticate(nil)
    assert_nil PersonalAccessToken.authenticate("")
    assert_nil PersonalAccessToken.authenticate("gs_pat_unknown")
    assert_nil PersonalAccessToken.authenticate(token.token.delete_prefix("gs_pat_")), "the prefix is required"
    assert_nil PersonalAccessToken.authenticate("gs_pat_#{'a' * 200}")
  end

  test "expired tokens stop authenticating" do
    token = create_token(expires_at: 1.hour.from_now)

    assert PersonalAccessToken.authenticate(token.token)
    travel 2.hours do
      assert_nil PersonalAccessToken.authenticate(token.token)
      assert token.reload.expired?
    end
  end

  test "revoked tokens stop authenticating" do
    token = create_token
    token.revoke

    assert token.revoked?
    assert_nil PersonalAccessToken.authenticate(token.token)
  end

  test "losing the membership stops the token at once" do
    token = create_token
    memberships(:jo_acme).destroy!

    assert_nil PersonalAccessToken.authenticate(token.token)
  end

  test "losing the membership revokes the tokens for that account, so re-joining doesn't revive them or keep cap slots" do
    token = create_token
    accounts(:umbrella).memberships.create!(user: users(:jo))
    other = users(:jo).personal_access_tokens.create!(account: accounts(:umbrella), name: "Other")
    memberships(:jo_acme).destroy!

    assert token.reload.revoked?
    assert_not other.reload.revoked?, "tokens for the accounts they still belong to keep working"
    assert_equal 0, users(:jo).personal_access_tokens.where(account: accounts(:acme)).active.count

    Membership.create!(account: accounts(:acme), user: users(:jo), role: "member")
    assert_nil PersonalAccessToken.authenticate(token.token)
  end

  test "the user must belong to the token's account" do
    token = users(:jo).personal_access_tokens.new(account: accounts(:umbrella), name: "Sneaky")

    assert_not token.save
    assert_includes token.errors[:account], "must be one you belong to"
  end

  test "caps active tokens per user; revoked and expired ones don't count" do
    (PersonalAccessToken::MAX_ACTIVE_PER_USER - 1).times { |n| create_token(name: "Token #{n}") }
    extra = users(:jo).personal_access_tokens.new(account: accounts(:acme), name: "One too many")
    assert_not extra.save
    assert_match(/at most 20 active tokens/, extra.errors.full_messages.to_sentence)

    users(:jo).personal_access_tokens.first.revoke
    assert extra.save
  end

  test "expiry choices" do
    now = Time.current
    assert_equal now + 30.days, PersonalAccessToken.expiry_for("30", now:)
    assert_equal now + 90.days, PersonalAccessToken.expiry_for("90", now:)
    assert_equal now + 365.days, PersonalAccessToken.expiry_for("365", now:)
    assert_nil PersonalAccessToken.expiry_for("never", now:)
    assert_equal now + 90.days, PersonalAccessToken.expiry_for("forever", now:), "unknown choices take the default"
  end

  test "records usage at most once per few minutes" do
    token = personal_access_tokens(:alex_read)
    assert_nil token.last_used_at

    token.record_usage
    first = token.reload.last_used_at
    assert first

    travel 1.minute do
      token.record_usage
      assert_equal first, token.reload.last_used_at
    end

    travel 6.minutes do
      token.record_usage
      assert_operator token.reload.last_used_at, :>, first
    end
  end

  test "the digest is filtered from inspect" do
    assert_includes personal_access_tokens(:alex_read).inspect, "token_digest: [FILTERED]"
  end
end
