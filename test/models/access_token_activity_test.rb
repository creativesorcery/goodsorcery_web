require "test_helper"

class AccessTokenActivityTest < ActiveSupport::TestCase
  test "records the token, its user, the action and the issue ids" do
    token = personal_access_tokens(:philip_triage)
    activity = AccessTokenActivity.record(token, "ignore", [ issues(:card_error).id ])

    assert_equal [ users(:philip).id, "ignore", [ issues(:card_error).id ] ], [ activity.user_id, activity.action, activity.issue_ids ]
    assert_equal "Ignored", activity.label
  end

  test "only known actions" do
    assert_raises(ActiveRecord::RecordInvalid) { AccessTokenActivity.record(personal_access_tokens(:philip_triage), "delete", []) }
  end

  test "recent_by_token keeps the newest 20 per token in one query" do
    token = personal_access_tokens(:philip_full)
    25.times { |n| AccessTokenActivity.create!(personal_access_token: token, user: users(:philip), action: "note", issue_ids: [ n ], created_at: n.minutes.ago) }

    recent = AccessTokenActivity.recent_by_token([ token.id, personal_access_tokens(:philip_triage).id ])

    assert_equal 20, recent[token.id].size
    assert_equal (0..19).to_a, recent[token.id].map { it.issue_ids.first }
    assert_equal 1, recent[personal_access_tokens(:philip_triage).id].size
  end

  test "deleting a token deletes its activity" do
    personal_access_tokens(:philip_triage).delete
    assert_equal 0, AccessTokenActivity.where(personal_access_token_id: personal_access_tokens(:philip_triage).id).count
  end

  test "pruning deletes long-ended tokens and old activity, and keeps the rest" do
    personal_access_tokens(:philip_revoked).update_columns(revoked_at: 91.days.ago)
    personal_access_tokens(:philip_expired).update_columns(expires_at: 89.days.ago)
    old = AccessTokenActivity.create!(personal_access_token: personal_access_tokens(:philip_read), user: users(:philip),
                                      action: "note", issue_ids: [], created_at: 91.days.ago)

    Ingest::Retention.new.prune_access_tokens

    assert_not PersonalAccessToken.exists?(personal_access_tokens(:philip_revoked).id)
    assert PersonalAccessToken.exists?(personal_access_tokens(:philip_expired).id)
    assert PersonalAccessToken.exists?(personal_access_tokens(:philip_full).id), "never-expiring tokens stay"
    assert_not AccessTokenActivity.exists?(old.id)
    assert AccessTokenActivity.exists?(access_token_activities(:philip_triage_resolved).id)
  end
end
