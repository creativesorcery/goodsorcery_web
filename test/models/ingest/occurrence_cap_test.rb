require "test_helper"

class Ingest::OccurrenceCapTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
  end

  # Storefront's fixtures store 2 nomethod and 1 regressed occurrence.
  def add_occurrences(issue, count)
    now = Time.current
    rows = Array.new(count) do
      { issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: now, received_at: now,
        environment: "production", level: "error", payload: "{}" }
    end
    Occurrence.insert_all(rows, returning: %i[id]).rows.flatten
  end

  def stored(issue) = Occurrence.where(issue:).count

  test "the level is the most copies each issue can keep within the cap, at least 1" do
    assert_equal 4, Ingest::OccurrenceCap.new(@project.id, cap: 6).level([ 8, 2 ])
    assert_equal 3_000, Ingest::OccurrenceCap.new(@project.id, cap: 3_000).level([ 3_000 ])
    assert_equal 1, Ingest::OccurrenceCap.new(@project.id, cap: 2).level([ 1, 1, 1 ])
  end

  test "trims the most repeated issue's oldest copies first" do
    ids = add_occurrences(issues(:card_error), 8)

    deleted = Ingest::OccurrenceCap.new(@project.id, cap: 6).enforce

    assert_equal 5, deleted
    assert_equal ids.max(3).sort, Occurrence.where(issue: issues(:card_error)).ids.sort
    assert_equal 2, stored(issues(:nomethod))
    assert_equal 1, stored(issues(:regressed))
  end

  test "every issue keeps its newest copy, even past the cap" do
    ids = add_occurrences(issues(:card_error), 4)

    Ingest::OccurrenceCap.new(@project.id, cap: 2).enforce

    assert_equal [ ids.max ], Occurrence.where(issue: issues(:card_error)).ids
    assert_equal 1, stored(issues(:nomethod))
    assert_equal 1, stored(issues(:regressed))
  end

  test "does nothing within the cap" do
    assert_no_difference(-> { Occurrence.count }) do
      assert_equal 0, Ingest::OccurrenceCap.new(@project.id, cap: 3).enforce
    end
  end

  test "enforce_all trims only the projects over the cap" do
    umbrella = Occurrence.where(project: projects(:umbrella_app)).count

    assert_equal 1, Ingest::OccurrenceCap.enforce_all(cap: 2)

    assert_equal 2, Occurrence.where(project: @project).count
    assert_equal umbrella, Occurrence.where(project: projects(:umbrella_app)).count
  end
end
