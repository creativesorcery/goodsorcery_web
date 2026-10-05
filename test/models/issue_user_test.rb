require "test_helper"

class IssueUserTest < ActiveSupport::TestCase
  test "count_for returns events for a user digest" do
    mara = PrivateDigest.hexdigest("user.id", "5521")
    assert_equal 7, IssueUser.count_for(issues(:nomethod), mara)
    assert_equal 0, IssueUser.count_for(issues(:card_error), mara)
  end

  test "distinct users across a project since a time" do
    assert_equal 2, IssueUser.distinct_users(projects(:storefront), since: 1.day.ago)
    assert_equal 1, IssueUser.distinct_users(projects(:storefront), since: 30.minutes.ago)
    assert_equal 0, IssueUser.distinct_users(projects(:billing), since: 1.day.ago)
  end

  test "identity digests for search cover every namespace" do
    digests = IssueUser.identity_digests_for(" Mara@Example.com ")
    assert_includes digests, PrivateDigest.hexdigest("user.email", "mara@example.com")
    assert_equal 3, digests.size
  end

  test "a 64-hex value is used as a digest directly" do
    digest = "A" * 64
    assert_equal [ digest.downcase ], IssueUser.identity_digests_for(digest)
  end

  test "no plaintext identity is stored" do
    row = IssueUser.connection.select_all("SELECT * FROM issue_users").rows.flatten.join(" ")
    assert_no_match(/mara|5521|example\.com/, row)
  end
end
