require "test_helper"

class PrivateDigestTest < ActiveSupport::TestCase
  test "is a stable 64-hex HMAC" do
    digest = PrivateDigest.hexdigest("user.email", "mara@example.com")

    assert_match(/\A\h{64}\z/, digest)
    assert_equal digest, PrivateDigest.hexdigest("user.email", "mara@example.com")
  end

  test "is namespaced and keyed" do
    assert_not_equal PrivateDigest.hexdigest("user.id", "1"), PrivateDigest.hexdigest("user.username", "1")
    assert_not_equal OpenSSL::Digest::SHA256.hexdigest("user.id:1"), PrivateDigest.hexdigest("user.id", "1")
  end

  test "recognises digests" do
    assert PrivateDigest.digest?("a" * 64)
    assert_not PrivateDigest.digest?("mara@example.com")
  end
end
