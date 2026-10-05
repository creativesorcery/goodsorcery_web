require "test_helper"

class Projects::CardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:philip)
  end

  test "renders one card in its frame without the layout" do
    get project_card_path(projects(:storefront))

    assert_response :success
    assert_select "aside", count: 0
    assert_select "turbo-frame##{dom_id(projects(:storefront), :card)}[target=_top]" do
      assert_select "a[href=?]", project_issues_path(projects(:storefront))
      assert_select ".chip", text: "production"
    end
  end

  test "a listening project's card links to setup" do
    get project_card_path(projects(:marketing))

    assert_select "turbo-frame##{dom_id(projects(:marketing), :card)} a[href=?]", project_setup_path(projects(:marketing))
  end

  test "is not stored by browsers" do
    get project_card_path(projects(:storefront))

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_card_path(projects(:storefront))

    assert_response :not_found
  end
end
