require "test_helper"

class Ingest::UserIdentityTest < ActiveSupport::TestCase
  test "digests present identifiers; the primary is the first of id, email, username" do
    identity = Ingest::UserIdentity.new({ "email" => " Mara@Example.com ", "username" => "mara" })
    assert identity.present?
    assert_equal PrivateDigest.hexdigest("user.email", "mara@example.com"), identity.primary_digest
    assert_equal [ PrivateDigest.hexdigest("user.email", "mara@example.com"), PrivateDigest.hexdigest("user.username", "mara") ],
                 identity.digests
  end

  test "matches the issue search digests" do
    identity = Ingest::UserIdentity.new({ "id" => "5521" })
    assert_includes IssueUser.identity_digests_for("5521"), identity.primary_digest
  end

  test "is absent without identifiers, even with a name" do
    identity = Ingest::UserIdentity.new({ "name" => "Mara" })
    assert_not identity.present?
    assert_nil identity.primary_digest
    assert_not Ingest::UserIdentity.new(nil).present?
  end
end
