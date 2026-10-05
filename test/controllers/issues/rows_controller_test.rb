require "test_helper"

class Issues::RowsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:philip)
  end

  test "renders one row in its frame" do
    get project_issue_row_path(@project, @issue)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@issue, :row)}[target=_top]" do
      assert_select ".text-coral-300", "NoMethodError"
      assert_select "a[href=?]", project_issue_path(@project, @issue)
      assert_select "svg rect", 24
      assert_select "input[type=checkbox][form=bulk_triage][value=?]", @issue.id.to_s
    end
  end

  test "unknown short id is a 404" do
    get project_issue_row_path(@project, "GS-999999")

    assert_response :not_found
  end

  test "an issue from another project of the account is a 404" do
    get project_issue_row_path(@project, "BA-7")

    assert_response :not_found
  end

  test "an outsider gets 404" do
    sign_in_as users(:outsider)

    get project_issue_row_path(@project, @issue)

    assert_response :not_found
  end
end
