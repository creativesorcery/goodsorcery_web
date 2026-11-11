require "test_helper"

class Issue::SearchableTest < ActiveSupport::TestCase
  setup { @issues = projects(:storefront).issues }

  test "status scopes" do
    assert_equal issues(:nomethod, :regressed, :card_error).sort, @issues.unresolved.sort
    assert_equal [ issues(:resolved_issue) ], @issues.resolved.to_a
    assert_equal [ issues(:ignored_issue) ], @issues.ignored.to_a
  end

  test "newly seen, regressed and for review" do
    assert_equal [ issues(:nomethod) ], @issues.newly_seen.to_a
    assert_equal [ issues(:regressed) ], @issues.regressed.to_a
    assert_equal issues(:nomethod, :regressed).sort, @issues.for_review.sort
  end

  test "in environment" do
    assert_equal [ issues(:regressed) ], @issues.in_environment("staging").to_a
    assert_equal 5, @issues.in_environment("production").count
    assert_empty @issues.in_environment("nope")
  end

  test "at level" do
    assert_equal [ issues(:card_error) ], @issues.at_level("warning").to_a
  end

  test "assignment scopes" do
    assert_equal [ issues(:nomethod) ], @issues.assigned_to(users(:alex)).to_a
    assert_equal issues(:regressed, :resolved_issue, :ignored_issue).sort, @issues.unassigned.sort
  end

  test "matching ANDs case-insensitive terms across class, message, culprit and transaction" do
    assert_equal [ issues(:nomethod) ], @issues.matching("PRICE_cents nil").to_a
    assert_equal [ issues(:nomethod) ], @issues.matching("cart_total.rb").to_a
    assert_equal [ issues(:regressed) ], @issues.matching("orders::placejob").to_a
    assert_empty @issues.matching("price_cents declined")
  end

  test "matching escapes LIKE wildcards" do
    assert_empty @issues.matching("%")
    assert_empty @issues.matching("_____________________________________________________________________________________________________________________________________________________________")
    assert_equal @issues.count, @issues.matching("  ").count
  end

  test "affecting finds issues by any identity digest" do
    email = PrivateDigest.hexdigest("user.email", "mara@example.com")
    assert_equal issues(:nomethod, :regressed).sort, @issues.affecting([ email ]).sort

    sam = IssueUser.identity_digests_for("sam@example.com")
    assert_equal [ issues(:nomethod) ], @issues.affecting(sam).to_a
    assert_empty @issues.affecting([ "0" * 64 ])
  end

  test "sorted by" do
    assert_equal issues(:nomethod), @issues.sorted_by("last_seen").first
    assert_equal issues(:nomethod), @issues.sorted_by(nil).first
    assert_equal issues(:nomethod), @issues.sorted_by("first_seen").first
    assert_equal issues(:card_error), @issues.sorted_by("events").first
    assert_equal issues(:nomethod), @issues.sorted_by("users").first
    assert_equal issues(:nomethod), @issues.sorted_by("'; drop table issues; --").first
  end
end
