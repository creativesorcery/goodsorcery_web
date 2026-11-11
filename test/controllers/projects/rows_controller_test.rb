require "test_helper"

class Projects::RowsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    sign_in_as users(:alex)
  end

  test "replaces each requested row of the project in one turbo stream response" do
    ids = [ issues(:nomethod), issues(:regressed) ].map(&:id)

    get project_rows_path(@project, ids: ids.join(","))

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    ids.each do |id|
      assert_select "turbo-stream[action=replace][target=row_issue_#{id}] template turbo-frame#row_issue_#{id}"
    end
  end

  test "uses a fixed number of queries however many rows are requested" do
    issues(:regressed).update!(assignee: users(:alex))
    one, all = [ issues(:regressed).id.to_s, @project.issues.ids.join(",") ].map { |ids| queries_for(ids) }

    assert_operator @project.issues.count, :>, 2
    assert_equal one, all
  end

  test "ignores other projects' issues and junk ids" do
    get project_rows_path(@project, ids: "#{issues(:billing_timeout).id},abc,,1e3")

    assert_response :success
    assert_select "turbo-stream", 0
  end

  test "an outsider gets 404" do
    sign_in_as users(:outsider)
    get project_rows_path(@project, ids: issues(:nomethod).id.to_s)

    assert_response :not_found
  end

  private
    def queries_for(ids)
      get project_rows_path(@project, ids:) # warm up
      count = 0
      callback = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get project_rows_path(@project, ids:) }
      count
    end
end
