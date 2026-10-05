require "test_helper"

class OccurrenceNavigatorTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:nomethod)
    @latest = occurrences(:nomethod_latest)
    @oldest = occurrences(:nomethod_oldest)
  end

  test "finds latest, oldest and by uuid" do
    assert_equal @latest, OccurrenceNavigator.new(@issue).find("latest")
    assert_equal @oldest, OccurrenceNavigator.new(@issue).find("oldest")
    assert_equal @oldest, OccurrenceNavigator.new(@issue).find(@oldest.uuid)
  end

  test "random picks one of the issue's occurrences" do
    10.times { assert_includes [ @latest, @oldest ], OccurrenceNavigator.new(@issue).find("random") }
  end

  test "only reaches the issue's own occurrences" do
    navigator = OccurrenceNavigator.new(@issue)

    assert_raises(ActiveRecord::RecordNotFound) { navigator.find(occurrences(:regressed_latest).uuid) }
    assert_raises(ActiveRecord::RecordNotFound) { navigator.find(occurrences(:umbrella_occurrence).uuid) }
    assert_raises(ActiveRecord::RecordNotFound) { navigator.find("not-a-uuid") }
  end

  test "shortcuts return nil when nothing is stored" do
    navigator = OccurrenceNavigator.new(issues(:card_error))

    assert_nil navigator.find("latest")
    assert_nil navigator.find("random")
    assert_equal 0, navigator.stored_count
    assert_nil navigator.selected_shortcut
  end

  test "position, neighbours and selection for the latest" do
    navigator = OccurrenceNavigator.new(@issue, occurrence: @latest)

    assert_equal [ 2, 2 ], [ navigator.position, navigator.stored_count ]
    assert_equal @oldest.uuid, navigator.older_uuid
    assert_nil navigator.newer_uuid
    assert_equal "latest", navigator.selected_shortcut
  end

  test "position, neighbours and selection for the oldest" do
    navigator = OccurrenceNavigator.new(@issue)
    navigator.find("oldest")

    assert_equal 1, navigator.position
    assert_nil navigator.older_uuid
    assert_equal @latest.uuid, navigator.newer_uuid
    assert_equal "oldest", navigator.selected_shortcut
  end

  test "random stays selected after a random pick" do
    navigator = OccurrenceNavigator.new(@issue)
    navigator.find("random")

    assert_equal "random", navigator.selected_shortcut
    assert_includes [ 1, 2 ], navigator.position
  end

  test "truncated when fewer are stored than counted" do
    assert OccurrenceNavigator.new(@issue, occurrence: @latest).truncated?

    @issue.events_count = 2
    assert_not OccurrenceNavigator.new(@issue, occurrence: @latest).truncated?
  end
end
